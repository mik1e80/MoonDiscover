param([switch]$Offline)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'toolchain.json') -Raw | ConvertFrom-Json
$toolsDir = Join-Path $projectRoot '.tools'
$localMoon = Join-Path $toolsDir 'moon'
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
$versionPath = $config.release.Replace('+', '%2B')
$originalPath = $env:PATH

function Get-VerifiedArchive($url, $path, $expected) {
    if (Test-Path -LiteralPath $path) {
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne $expected) { throw "Archive checksum mismatch: $path" }
        return
    }
    if ($Offline) { throw "Missing archive in offline mode: $path" }
    $partial = "$path.download"
    Invoke-WebRequest -Uri $url -OutFile $partial
    $actual = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
    if ($actual -ne $expected) { throw "Archive checksum mismatch: $partial" }
    Move-Item -LiteralPath $partial -Destination $path
}

$compiler = Join-Path $localMoon 'bin\moonc.exe'
$installed = if (Test-Path -LiteralPath $compiler) { (& $compiler -v) -join "`n" } else { '' }
$installMoon = $localMoon
if (-not $installed.Contains($config.moonc)) {
    $binaryZip = Join-Path $toolsDir "moonbit-$($config.release).zip"
    $coreZip = Join-Path $toolsDir "core-$($config.release).zip"
    Get-VerifiedArchive "https://cli.moonbitlang.com/binaries/$versionPath/moonbit-windows-x86_64.zip" $binaryZip $config.windows_archive_sha256
    Get-VerifiedArchive "https://cli.moonbitlang.com/cores/core-$versionPath.zip" $coreZip $config.core_archive_sha256
    $installMoon = Join-Path $toolsDir ("moon-stage-" + [guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $binaryZip -DestinationPath $installMoon
    Expand-Archive -LiteralPath $coreZip -DestinationPath (Join-Path $installMoon 'lib')
}
$env:MOON_HOME = $installMoon
$env:PATH = (Join-Path $installMoon 'bin') + ';' + $originalPath
$moonExe = Join-Path $installMoon 'bin\moon.exe'
$versions = (& $moonExe version --all) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $versions.Contains($config.moonc)) { throw 'Unexpected toolchain version' }
Write-Output $versions
Push-Location (Join-Path $installMoon 'lib\core')
try {
    foreach ($target in @('js', 'native', 'wasm', 'wasm-gc')) {
        & $moonExe bundle --target $target --quiet
        if ($LASTEXITCODE -ne 0) { throw "Core bundle failed: $target" }
    }
} finally { Pop-Location }
if ($installMoon -ne $localMoon) {
    if (Test-Path -LiteralPath $localMoon) {
        $backup = Join-Path $toolsDir ("moon-previous-" + [guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $localMoon -Destination $backup
    }
    Move-Item -LiteralPath $installMoon -Destination $localMoon
}
$env:MOON_HOME = $localMoon
$env:PATH = (Join-Path $localMoon 'bin') + ';' + $originalPath
$moonExe = Join-Path $localMoon 'bin\moon.exe'
if (-not $Offline) {
    Push-Location $projectRoot
    try {
        & $moonExe update
        if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
    } finally { Pop-Location }
}
Write-Output 'Project toolchain ready. Use scripts/moon.ps1 for project commands.'
