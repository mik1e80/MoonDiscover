#include <stdint.h>
#include <string.h>
#include <moonbit.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET ttl_socket;
#define TTL_INVALID INVALID_SOCKET
#define TTL_CLOSE closesocket
#define TTL_SET(s,l,o,v,n) setsockopt(s,l,o,(const char *)(v),n)
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
typedef int ttl_socket;
#define TTL_INVALID (-1)
#define TTL_CLOSE close
#define TTL_SET setsockopt
#endif
MOONBIT_FFI_EXPORT int64_t md_ttl_open(void) {
#ifdef _WIN32
  WSADATA data;
  if (WSAStartup(MAKEWORD(2,2), &data)) return -1;
  ttl_socket s = WSASocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, NULL, 0, WSA_FLAG_NO_HANDLE_INHERIT);
#else
  ttl_socket s = socket(AF_INET, SOCK_DGRAM, 0);
#endif
  int yes = 1;
  struct sockaddr_in address;
  memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(0x7f000001U);
  if (s == TTL_INVALID || TTL_SET(s, IPPROTO_IP, IP_PKTINFO, &yes, sizeof(yes)) ||
      TTL_SET(s, IPPROTO_IP, IP_RECVTTL, &yes, sizeof(yes)) || bind(s, (struct sockaddr *)&address, sizeof(address))) {
    if (s != TTL_INVALID) TTL_CLOSE(s);
#ifdef _WIN32
    WSACleanup();
#endif
    return -1;
  }
  return (int64_t)s;
}
MOONBIT_FFI_EXPORT int md_ttl_port(int64_t handle) {
  struct sockaddr_in address;
#ifdef _WIN32
  int size = sizeof(address);
#else
  socklen_t size = sizeof(address);
#endif
  return getsockname((ttl_socket)handle, (struct sockaddr *)&address, &size) ? -1 : ntohs(address.sin_port);
}
MOONBIT_FFI_EXPORT int md_ttl_send(int port, int ttl) {
#ifdef _WIN32
  ttl_socket s = WSASocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, NULL, 0, WSA_FLAG_NO_HANDLE_INHERIT);
#else
  ttl_socket s = socket(AF_INET, SOCK_DGRAM, 0);
#endif
  if (s == TTL_INVALID) return -1;
  struct sockaddr_in target;
  memset(&target, 0, sizeof(target)); target.sin_family = AF_INET;
  target.sin_addr.s_addr = htonl(0x7f000001U); target.sin_port = htons((uint16_t)port);
  char bytes[12] = {0,0,(char)0x84,0,0,0,0,0,0,0,0,0}; bytes[11] = (char)ttl;
  int result = TTL_SET(s, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) ? -1 : (int)sendto(s, bytes, 12, 0, (struct sockaddr *)&target, sizeof(target));
  TTL_CLOSE(s); return result;
}

/* Test-only route lookup, without sending an application datagram. */
MOONBIT_FFI_EXPORT uint32_t md_ttl_interface(void) {
#ifdef _WIN32
  WSADATA data;
  if (WSAStartup(MAKEWORD(2,2), &data)) return 0;
  ttl_socket s = WSASocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, NULL, 0, WSA_FLAG_NO_HANDLE_INHERIT);
  int size;
#else
  ttl_socket s = socket(AF_INET, SOCK_DGRAM, 0);
  socklen_t size;
#endif
  uint32_t result = 0;
  struct sockaddr_in address;
  memset(&address, 0, sizeof(address)); address.sin_family = AF_INET;
  address.sin_port = htons(5353); address.sin_addr.s_addr = htonl(0xe00000fbU);
  if (s != TTL_INVALID && !connect(s, (struct sockaddr *)&address, sizeof(address))) {
    size = sizeof(address);
    if (!getsockname(s, (struct sockaddr *)&address, &size)) result = ntohl(address.sin_addr.s_addr);
  }
  if (s != TTL_INVALID) TTL_CLOSE(s);
#ifdef _WIN32
  WSACleanup();
#endif
  return result;
}
