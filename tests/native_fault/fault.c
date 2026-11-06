/* Test-only copy of the real shim, with OS call interposition. Production has
   no environment switches or fault hooks. */
#include <stdint.h>
#include <moonbit.h>
static int md_stage, md_step, md_opened, md_closed;
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
static int md_bad(void) { WSASetLastError(WSAEINVAL); return -1; }
static SOCKET md_socket_call(int af, int type, int proto, LPWSAPROTOCOL_INFOA info, GROUP group, DWORD flags) {
  SOCKET s = WSASocketA(af, type, proto, info, group, flags); if (s != INVALID_SOCKET) md_opened++; return s;
}
static int md_close_call(SOCKET s) { md_closed++; return closesocket(s); }
static int md_set_call(SOCKET s, int level, int option, const char *value, int length) {
  if (option != IP_RECVTTL && ++md_step == md_stage) return md_bad();
  return setsockopt(s, level, option, value, length);
}
static int md_bind_call(SOCKET s, const struct sockaddr *a, int length) { if (++md_step == md_stage) return md_bad(); return bind(s, a, length); }
static int md_send_call(SOCKET s, const char *b, int n, int flags, const struct sockaddr *a, int length) { if (md_stage == 101) return md_bad(); return sendto(s, b, n, flags, a, length); }
static int md_select_call(int n, fd_set *r, fd_set *w, fd_set *e, const struct timeval *t) { if (md_stage == 100) return md_bad(); return select(n, r, w, e, t); }
#undef WSASocket
#define WSASocket md_socket_call
#define closesocket md_close_call
#define select md_select_call
#else
#include <sys/socket.h>
#include <poll.h>
#include <unistd.h>
#include <errno.h>
#include <netinet/in.h>
static int md_bad(void) { errno = EIO; return -1; }
static int md_socket_call(int af, int type, int protocol) { int s = socket(af, type, protocol); if (s >= 0) md_opened++; return s; }
static int md_close_call(int s) { md_closed++; return close(s); }
static int md_set_call(int s, int level, int option, const void *v, socklen_t n) {
  if (option != IP_RECVTTL && ++md_step == md_stage) return md_bad();
  return setsockopt(s, level, option, v, n);
}
static int md_bind_call(int s, const struct sockaddr *a, socklen_t n) { if (++md_step == md_stage) return md_bad(); return bind(s, a, n); }
static ssize_t md_send_call(int s, const void *b, size_t n, int flags, const struct sockaddr *a, socklen_t size) { if (md_stage == 101) return md_bad(); return sendto(s, b, n, flags, a, size); }
static int md_poll_call(struct pollfd *p, nfds_t n, int t) { if (md_stage == 100) return md_bad(); return poll(p, n, t); }
#define socket md_socket_call
#define close md_close_call
#define poll md_poll_call
#endif
#define setsockopt md_set_call
#define bind md_bind_call
#define sendto md_send_call
#define moondiscover_socket_open md_probe_open
#define moondiscover_socket_close md_probe_close
#define moondiscover_socket_send md_probe_send
#define moondiscover_socket_receive md_probe_receive
#define moondiscover_interface_index md_probe_interface_index
#define moondiscover_monotonic_ms md_probe_clock
#include "../../src/native/socket.c"
MOONBIT_FFI_EXPORT void md_probe_failure(int stage) { md_stage = stage; md_step = 0; md_opened = 0; md_closed = 0; }
MOONBIT_FFI_EXPORT int md_probe_balance(void) { return md_opened - md_closed; }
