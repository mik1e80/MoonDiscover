#include <stdint.h>
#include <moonbit.h>
#ifdef _WIN32
#define PSAPI_VERSION 2
#include <windows.h>
#include <psapi.h>
#else
#include <stdio.h>
#include <unistd.h>
#include <dirent.h>
#endif

/* Test-only scalar probes. No MoonBit data or retained pointers cross the ABI. */
MOONBIT_FFI_EXPORT int64_t moondiscover_probe_rss(void) {
#ifdef _WIN32
  PROCESS_MEMORY_COUNTERS counters;
  if (!K32GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters))) return -1;
  return (int64_t)counters.WorkingSetSize;
#else
  long pages = 0, resident = 0;
  FILE *f = fopen("/proc/self/statm", "r");
  if (!f) return -1;
  int count = fscanf(f, "%ld %ld", &pages, &resident);
  fclose(f);
  return count == 2 ? (int64_t)resident * sysconf(_SC_PAGESIZE) : -1;
#endif
}

MOONBIT_FFI_EXPORT int64_t moondiscover_probe_handles(void) {
#ifdef _WIN32
  DWORD count = 0;
  return GetProcessHandleCount(GetCurrentProcess(), &count) ? (int64_t)count : -1;
#else
  DIR *dir = opendir("/proc/self/fd");
  if (!dir) return -1;
  int64_t count = 0;
  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (entry->d_name[0] != '.') count++;
  }
  closedir(dir);
  return count;
#endif
}
