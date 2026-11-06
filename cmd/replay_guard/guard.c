#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>

static wchar_t *md_wide(const char *text) {
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
  if (!n) return NULL;
  wchar_t *out = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
  if (out && !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, out, n)) { free(out); return NULL; }
  return out;
}

/* CRT argument quoting. No shell is invoked. */
static wchar_t *md_command(const wchar_t *path) {
  size_t n = wcslen(path), at = 0, slashes = 0;
  wchar_t *out = (wchar_t *)calloc(2*n + 64, sizeof(wchar_t));
  if (!out) return NULL;
  const wchar_t *prefix = L"moondiscover replay --file \"";
  while (*prefix) out[at++] = *prefix++;
  for (size_t i = 0; i < n; i++) {
    if (path[i] == L'\\') { slashes++; continue; }
    size_t copies = path[i] == L'"' ? slashes * 2 + 1 : slashes;
    while (copies--) out[at++] = L'\\';
    slashes = 0;
    out[at++] = path[i];
  }
  while (slashes--) { out[at++] = L'\\'; out[at++] = L'\\'; }
  out[at++] = L'"'; out[at] = 0;
  return out;
}

MOONBIT_FFI_EXPORT int moondiscover_guard_replay(const char *exe, const char *trace, int wall, int memory, int cpu, int64_t *metrics) {
  int result = -1;
  HANDLE job = NULL, nul = INVALID_HANDLE_VALUE;
  wchar_t *program = md_wide(exe), *file = md_wide(trace), *command = NULL;
  PROCESS_INFORMATION process;
  STARTUPINFOEXW startup;
  memset(&process, 0, sizeof(process)); memset(&startup, 0, sizeof(startup));
  memset(metrics, 0, 3 * sizeof(int64_t));
  ULONGLONG begin = GetTickCount64();
  if (!program || !file || !(command = md_command(file))) goto done;
  job = CreateJobObjectW(NULL, NULL);
  if (!job) goto done;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
  memset(&limits, 0, sizeof(limits));
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_PROCESS_MEMORY | JOB_OBJECT_LIMIT_PROCESS_TIME;
  limits.BasicLimitInformation.PerProcessUserTimeLimit.QuadPart = (LONGLONG)cpu * 10000000;
  limits.ProcessMemoryLimit = (SIZE_T)memory * 1024 * 1024;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) goto done;
  SECURITY_ATTRIBUTES security = { sizeof(security), NULL, TRUE };
  nul = CreateFileW(L"NUL", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, NULL);
  if (nul == INVALID_HANDLE_VALUE) goto done;
  SIZE_T attributes = 0;
  InitializeProcThreadAttributeList(NULL, 1, 0, &attributes);
  startup.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(attributes);
  if (!startup.lpAttributeList) goto done;
  if (!InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attributes)) { free(startup.lpAttributeList); startup.lpAttributeList = NULL; goto done; }
  if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, &nul, sizeof(nul), NULL, NULL)) goto done;
  startup.StartupInfo.cb = sizeof(startup);
  startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup.StartupInfo.hStdInput = startup.StartupInfo.hStdOutput = startup.StartupInfo.hStdError = nul;
  if (!CreateProcessW(program, command, NULL, NULL, TRUE, CREATE_SUSPENDED | CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT, NULL, NULL, &startup.StartupInfo, &process)) goto done;
  if (!AssignProcessToJobObject(job, process.hProcess)) { TerminateProcess(process.hProcess, 126); goto done; }
  if (ResumeThread(process.hThread) == (DWORD)-1) { TerminateJobObject(job, 126); goto done; }
  for (;;) {
    DWORD waited = WaitForSingleObject(process.hProcess, 10);
    if (waited == WAIT_OBJECT_0) break;
    FILETIME created, ended, kernel, user;
    ULARGE_INTEGER k, u;
    DWORD termination = 0;
    if (waited != WAIT_TIMEOUT || !GetProcessTimes(process.hProcess, &created, &ended, &kernel, &user)) termination = 126;
    else {
      k.LowPart = kernel.dwLowDateTime; k.HighPart = kernel.dwHighDateTime;
      u.LowPart = user.dwLowDateTime; u.HighPart = user.dwHighDateTime;
      if (k.QuadPart + u.QuadPart >= (ULONGLONG)cpu * 10000000) { metrics[2] = 2; termination = 125; }
      else if (GetTickCount64() - begin >= (ULONGLONG)wall) { metrics[2] = 1; termination = 124; }
    }
    if (termination) { TerminateJobObject(job, termination); WaitForSingleObject(process.hProcess, 5000); break; }
  }
  DWORD exit_code = 126;
  GetExitCodeProcess(process.hProcess, &exit_code);
  if (exit_code && !metrics[2]) {
    FILETIME created, ended, kernel, user; ULARGE_INTEGER k, u;
    if (GetProcessTimes(process.hProcess, &created, &ended, &kernel, &user)) {
      k.LowPart = kernel.dwLowDateTime; k.HighPart = kernel.dwHighDateTime;
      u.LowPart = user.dwLowDateTime; u.HighPart = user.dwHighDateTime;
      if (k.QuadPart + u.QuadPart >= (ULONGLONG)cpu * 10000000) metrics[2] = 2;
    }
  }
  result = metrics[2] == 1 ? 124 : metrics[2] == 2 ? 125 : (int)exit_code;
  if (QueryInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits), NULL)) metrics[1] = (int64_t)limits.PeakProcessMemoryUsed;
done:
  if (result < 0 && process.hProcess) { TerminateProcess(process.hProcess, 126); WaitForSingleObject(process.hProcess, 5000); }
  if (process.hThread) CloseHandle(process.hThread);
  if (process.hProcess) CloseHandle(process.hProcess);
  if (startup.lpAttributeList) { DeleteProcThreadAttributeList(startup.lpAttributeList); free(startup.lpAttributeList); }
  if (nul != INVALID_HANDLE_VALUE) CloseHandle(nul);
  if (job) CloseHandle(job);
  free(program); free(file); free(command);
  metrics[0] = (int64_t)(GetTickCount64() - begin);
  return result;
}
#else
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <time.h>
static int64_t md_ms(void) { struct timespec t; return clock_gettime(CLOCK_MONOTONIC, &t) ? -1 : (int64_t)t.tv_sec*1000 + t.tv_nsec/1000000; }
MOONBIT_FFI_EXPORT int moondiscover_guard_replay(const char *exe, const char *trace, int wall, int memory, int cpu, int64_t *metrics) {
  memset(metrics, 0, 3 * sizeof(int64_t));
  int64_t begin = md_ms();
  if (begin < 0) return -1;
  pid_t child = fork();
  if (child < 0) return -1;
  if (child == 0) {
    if (setpgid(0, 0)) _exit(126);
    struct rlimit address = { (rlim_t)memory * 1024 * 1024, (rlim_t)memory * 1024 * 1024 };
    struct rlimit seconds = { (rlim_t)cpu, (rlim_t)cpu };
    struct rlimit core = { 0, 0 };
    if (setrlimit(RLIMIT_AS, &address) || setrlimit(RLIMIT_CPU, &seconds) || setrlimit(RLIMIT_CORE, &core)) _exit(126);
    int nul = open("/dev/null", O_RDWR);
    if (nul < 0 || dup2(nul, 0) < 0 || dup2(nul, 1) < 0 || dup2(nul, 2) < 0) _exit(126);
    if (nul > 2) close(nul);
    char *const args[] = { (char *)exe, "replay", "--file", (char *)trace, NULL };
    execv(exe, args); _exit(127);
  }
  /* Either parent or child may establish the group first. */
  (void)setpgid(child, child);
  int status = 0;
  struct rusage usage;
  memset(&usage, 0, sizeof(usage));
  for (;;) {
    pid_t waited = wait4(child, &status, WNOHANG, &usage);
    if (waited == child) break;
    if (waited < 0 && errno != EINTR) { kill(-child, SIGKILL); kill(child, SIGKILL); return -1; }
    int64_t now = md_ms();
    if (now < 0 || now - begin >= wall) {
      metrics[2] = 1;
      kill(-child, SIGKILL); kill(child, SIGKILL);
      while (wait4(child, &status, 0, &usage) < 0 && errno == EINTR) { }
      break;
    }
    struct timespec pause = { 0, 5000000 };
    nanosleep(&pause, NULL);
  }
  metrics[0] = md_ms() - begin;
  metrics[1] = (int64_t)usage.ru_maxrss * 1024;
  if (metrics[2]) return 124;
  if (WIFSIGNALED(status) && (WTERMSIG(status) == SIGXCPU || WTERMSIG(status) == SIGKILL) &&
      usage.ru_utime.tv_sec + usage.ru_stime.tv_sec >= cpu - 1) metrics[2] = 2;
  return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
#endif
