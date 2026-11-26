#include "../resource_soak/resource.c"

#ifdef _WIN32
#include <processsnapshot.h>
#include <stdio.h>
#include <wchar.h>

static const char *handle_kind(const PSS_HANDLE_ENTRY *entry, char kind[64]) {
  if (!entry->TypeName) return "Unknown";
  size_t length = entry->TypeNameLength / sizeof(wchar_t);
  while (length > 0 && entry->TypeName[length - 1] == L'\0') --length;
  if (length == 4 && wmemcmp(entry->TypeName, L"File", 4) == 0) {
    if (entry->ObjectName) {
      size_t size = entry->ObjectNameLength / sizeof(wchar_t);
      if (size >= 11 && _wcsnicmp(entry->ObjectName, L"\\Device\\Afd", 11) == 0)
        return "File:Afd";
      if (size >= 11 && _wcsnicmp(entry->ObjectName, L"\\Device\\Nsi", 11) == 0)
        return "File:Nsi";
    }
    return "File";
  }
  if (length == 0 || length >= 64) return "Unknown";
  for (size_t i = 0; i < length; ++i) {
    wchar_t ch = entry->TypeName[i];
    if (!((ch >= L'A' && ch <= L'Z') || (ch >= L'a' && ch <= L'z') ||
          (ch >= L'0' && ch <= L'9') || ch == L' ' || ch == L'_'))
      return "Unknown";
    kind[i] = (char)ch;
  }
  kind[length] = '\0';
  return kind;
}
#endif

/* Diagnostic only. A snapshot is released before returning and paths are
   never exported. The buffer is borrowed for this synchronous call. */
MOONBIT_FFI_EXPORT int32_t moondiscover_probe_snapshot(char *output, int32_t size) {
#ifdef _WIN32
  if (size < 3) return -ERROR_INSUFFICIENT_BUFFER;
  const HANDLE process = GetCurrentProcess();
  HPSS snapshot;
  DWORD status = PssCaptureSnapshot(process,
    PSS_CAPTURE_HANDLES | PSS_CAPTURE_HANDLE_NAME_INFORMATION |
    PSS_CAPTURE_HANDLE_TYPE_SPECIFIC_INFORMATION, 0, &snapshot);
  if (status != ERROR_SUCCESS) return -(int32_t)status;
  HPSSWALK marker;
  status = PssWalkMarkerCreate(NULL, &marker);
  int32_t used = 1;
  output[0] = '[';
  if (status == ERROR_SUCCESS) {
    PSS_HANDLE_ENTRY entry;
    while ((status = PssWalkSnapshot(snapshot, PSS_WALK_HANDLES,
        marker, &entry, sizeof(entry))) == ERROR_SUCCESS) {
      char kind[64];
      int count = snprintf(output + used, (size_t)(size - used), "%s[%llu,\"%s\"]",
        used == 1 ? "" : ",", (unsigned long long)(uintptr_t)entry.Handle,
        handle_kind(&entry, kind));
      if (count < 0 || count >= size - used - 1) {
        status = ERROR_INSUFFICIENT_BUFFER;
        break;
      }
      used += count;
    }
    if (status == ERROR_NO_MORE_ITEMS) status = ERROR_SUCCESS;
    DWORD cleanup = PssWalkMarkerFree(marker);
    if (status == ERROR_SUCCESS) status = cleanup;
  }
  DWORD cleanup = PssFreeSnapshot(process, snapshot);
  if (status == ERROR_SUCCESS) status = cleanup;
  if (status != ERROR_SUCCESS) return -(int32_t)status;
  output[used++] = ']';
  return used;
#else
  (void)output;
  (void)size;
  return -1;
#endif
}
