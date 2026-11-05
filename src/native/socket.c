/* MoonDiscover's minimal IPv4 transport shim. Protocol logic lives in MoonBit. */
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <moonbit.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <mswsock.h>
#include <iphlpapi.h>
#include <netioapi.h>
#pragma comment(lib, "Ws2_32.lib")
#pragma comment(lib, "Iphlpapi.lib")
typedef SOCKET md_socket;
#define MD_ERROR() WSAGetLastError()
#define MD_CLOSE(s) closesocket(s)
#define MD_INVALID INVALID_SOCKET
#define MD_SET(s,l,o,v,n) setsockopt(s,l,o,(const char *)(v),n)
#else
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <time.h>
typedef int md_socket;
#define MD_ERROR() errno
#define MD_CLOSE(s) close(s)
#define MD_INVALID (-1)
#define MD_SET setsockopt
#endif

MOONBIT_FFI_EXPORT int64_t moondiscover_monotonic_ms(void) {
#ifdef _WIN32
  return (int64_t)GetTickCount64();
#else
  struct timespec t;
  if (clock_gettime(CLOCK_MONOTONIC, &t) != 0) return -1;
  return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
#endif
}

MOONBIT_FFI_EXPORT int moondiscover_interface_index(uint32_t ip) {
#ifdef _WIN32
  ULONG size = 0;
  DWORD status = GetIpAddrTable(NULL, &size, FALSE);
  if (status != ERROR_INSUFFICIENT_BUFFER) return -(int)status;
  MIB_IPADDRTABLE *table = (MIB_IPADDRTABLE *)malloc(size);
  if (!table) return -ERROR_NOT_ENOUGH_MEMORY;
  status = GetIpAddrTable(table, &size, FALSE);
  int index = 0;
  if (status == NO_ERROR) {
    for (DWORD i = 0; i < table->dwNumEntries; i++) {
      if (table->table[i].dwAddr == htonl(ip)) {
        MIB_IF_ROW2 row;
        memset(&row, 0, sizeof(row));
        row.InterfaceIndex = table->table[i].dwIndex;
        if (GetIfEntry2(&row) == NO_ERROR && row.OperStatus == IfOperStatusUp)
          index = (int)row.InterfaceIndex;
        break;
      }
    }
  }
  free(table);
  return status == NO_ERROR ? index : -(int)status;
#else
  struct ifaddrs *addresses = NULL;
  if (getifaddrs(&addresses) != 0) return -errno;
  int index = 0;
  for (struct ifaddrs *p = addresses; p; p = p->ifa_next) {
    if (p->ifa_addr && p->ifa_addr->sa_family == AF_INET &&
        (p->ifa_flags & IFF_UP) && (p->ifa_flags & IFF_RUNNING) &&
        ((struct sockaddr_in *)p->ifa_addr)->sin_addr.s_addr == htonl(ip)) {
      index = (int)if_nametoindex(p->ifa_name);
      break;
    }
  }
  freeifaddrs(addresses);
  return index;
#endif
}

MOONBIT_FFI_EXPORT int64_t moondiscover_socket_open(uint32_t ip) {
#ifdef _WIN32
  WSADATA wsa;
  int startup = WSAStartup(MAKEWORD(2, 2), &wsa);
  if (startup) return -(int64_t)startup;
  md_socket s = WSASocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, NULL, 0,
                         WSA_FLAG_NO_HANDLE_INHERIT);
#else
  md_socket s = socket(AF_INET, SOCK_DGRAM, 0);
#endif
  int err = 0, yes = 1, ttl = 255;
  struct sockaddr_in local;
  struct ip_mreq membership;
  struct in_addr iface;
  if (s == MD_INVALID) { err = MD_ERROR(); goto failure; }
#ifndef _WIN32
  if (fcntl(s, F_SETFD, FD_CLOEXEC) < 0) { err = MD_ERROR(); goto failure; }
#endif
  if (MD_SET(s, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes)) != 0) goto socket_failure;
  if (MD_SET(s, IPPROTO_IP, IP_PKTINFO, &yes, sizeof(yes)) != 0) goto socket_failure;
  /* Optional ancillary TTL. Failure leaves it absent; strict policy rejects it.
     IP_RECVTTL enables it; providers may use IP_TTL or IP_RECVTTL cmsgs. */
#ifdef IP_RECVTTL
  (void)MD_SET(s, IPPROTO_IP, IP_RECVTTL, &yes, sizeof(yes));
#endif
  memset(&local, 0, sizeof(local));
  local.sin_family = AF_INET;
  local.sin_port = htons(5353);
  local.sin_addr.s_addr = htonl(INADDR_ANY);
  if (bind(s, (struct sockaddr *)&local, sizeof(local)) != 0) goto socket_failure;
  iface.s_addr = htonl(ip);
  membership.imr_multiaddr.s_addr = htonl(0xe00000fbu);
  membership.imr_interface = iface;
  if (MD_SET(s, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, sizeof(membership)) != 0) goto socket_failure;
  if (MD_SET(s, IPPROTO_IP, IP_MULTICAST_IF, &iface, sizeof(iface)) != 0) goto socket_failure;
  if (MD_SET(s, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl)) != 0) goto socket_failure;
#ifdef _WIN32
  { u_long nonblocking = 1;
    if (ioctlsocket(s, FIONBIO, &nonblocking) != 0) goto socket_failure;
  }
#endif
  return (int64_t)s;
socket_failure:
  err = MD_ERROR();
failure:
  if (s != MD_INVALID) MD_CLOSE(s);
#ifdef _WIN32
  WSACleanup();
#endif
  return -(int64_t)(err ? err : 1);
}

MOONBIT_FFI_EXPORT void moondiscover_socket_close(int64_t handle) {
  MD_CLOSE((md_socket)handle);
#ifdef _WIN32
  WSACleanup();
#endif
}

MOONBIT_FFI_EXPORT int moondiscover_socket_send(int64_t handle, const char *data, int size) {
  struct sockaddr_in target;
  memset(&target, 0, sizeof(target));
  target.sin_family = AF_INET;
  target.sin_port = htons(5353);
  target.sin_addr.s_addr = htonl(0xe00000fbu);
  int n = sendto((md_socket)handle, data, size, 0, (struct sockaddr *)&target, sizeof(target));
  return n < 0 ? -MD_ERROR() : n;
}

MOONBIT_FFI_EXPORT int moondiscover_socket_receive(
    int64_t handle, char *data, int size, int32_t *metadata, int timeout_ms) {
  md_socket s = (md_socket)handle;
  struct sockaddr_in source;
  memset(&source, 0, sizeof(source));
  memset(metadata, 0, 5 * sizeof(int32_t));
  metadata[4] = -1;
#ifdef _WIN32
  fd_set readable;
  FD_ZERO(&readable);
  FD_SET(s, &readable);
  struct timeval timeout = { timeout_ms / 1000, (timeout_ms % 1000) * 1000 };
  int ready = select(0, &readable, NULL, NULL, &timeout);
  if (ready <= 0) return ready == 0 ? 0 : -MD_ERROR();
  GUID id = WSAID_WSARECVMSG;
  LPFN_WSARECVMSG recv_message = NULL;
  DWORD returned = 0;
  if (WSAIoctl(s, SIO_GET_EXTENSION_FUNCTION_POINTER, &id, sizeof(id),
               &recv_message, sizeof(recv_message), &returned, NULL, NULL) != 0) return -MD_ERROR();
  WSABUF buffer = { (ULONG)size, data };
  /* Union makes ancillary data suitably aligned for WSACMSGHDR. */
  union { WSACMSGHDR alignment; char bytes[256]; } control;
  WSAMSG msg;
  memset(&msg, 0, sizeof(msg));
  msg.name = (SOCKADDR *)&source;
  msg.namelen = sizeof(source);
  msg.lpBuffers = &buffer;
  msg.dwBufferCount = 1;
  msg.Control.buf = control.bytes;
  msg.Control.len = sizeof(control.bytes);
  DWORD count = 0;
  if (recv_message(s, &msg, &count, NULL, NULL) != 0) {
    int err = MD_ERROR();
    /* Datagram truncation consumes an untrusted packet, not the socket.
       Return a length sentinel rather than a platform-specific socket error. */
    if (err == WSAEMSGSIZE) return size + 1;
    return err == WSAEWOULDBLOCK || err == WSAEINTR ? 0 : -err;
  }
  if (msg.dwFlags & (MSG_TRUNC | MSG_CTRUNC)) return size + 1;
  for (WSACMSGHDR *c = WSA_CMSG_FIRSTHDR(&msg); c; c = WSA_CMSG_NXTHDR(&msg, c)) {
    if (c->cmsg_level == IPPROTO_IP && c->cmsg_type == IP_PKTINFO &&
        c->cmsg_len >= WSA_CMSG_LEN(sizeof(IN_PKTINFO))) {
      IN_PKTINFO *info = (IN_PKTINFO *)WSA_CMSG_DATA(c);
      metadata[2] = (int32_t)info->ipi_ifindex;
      metadata[3] = (int32_t)ntohl(info->ipi_addr.s_addr);
    }
#ifdef IP_RECVTTL
    if (c->cmsg_level == IPPROTO_IP &&
        (c->cmsg_type == IP_RECVTTL || c->cmsg_type == IP_TTL) &&
        c->cmsg_len >= WSA_CMSG_LEN(sizeof(DWORD))) {
      DWORD ttl;
      memcpy(&ttl, WSA_CMSG_DATA(c), sizeof(ttl));
      if (ttl <= 255) metadata[4] = (int32_t)ttl;
    }
#endif
  }
#else
  struct pollfd p = { s, POLLIN, 0 };
  int ready = poll(&p, 1, timeout_ms);
  if (ready <= 0) return ready == 0 ? 0 : -errno;
  struct iovec buffer = { data, (size_t)size };
  union { struct cmsghdr alignment; char bytes[256]; } control;
  struct msghdr msg;
  memset(&msg, 0, sizeof(msg));
  msg.msg_name = &source;
  msg.msg_namelen = sizeof(source);
  msg.msg_iov = &buffer;
  msg.msg_iovlen = 1;
  msg.msg_control = control.bytes;
  msg.msg_controllen = sizeof(control.bytes);
  int count = (int)recvmsg(s, &msg, MSG_DONTWAIT);
  if (count < 0) return errno == EAGAIN || errno == EINTR ? 0 : -errno;
  if (msg.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) return size + 1;
  for (struct cmsghdr *c = CMSG_FIRSTHDR(&msg); c; c = CMSG_NXTHDR(&msg, c)) {
    if (c->cmsg_level == IPPROTO_IP && c->cmsg_type == IP_PKTINFO &&
        c->cmsg_len >= CMSG_LEN(sizeof(struct in_pktinfo))) {
      struct in_pktinfo *info = (struct in_pktinfo *)CMSG_DATA(c);
      metadata[2] = (int32_t)info->ipi_ifindex;
      metadata[3] = (int32_t)ntohl(info->ipi_addr.s_addr);
    }
    if (c->cmsg_level == IPPROTO_IP && c->cmsg_type == IP_TTL &&
        c->cmsg_len >= CMSG_LEN(sizeof(int))) {
      int ttl;
      memcpy(&ttl, CMSG_DATA(c), sizeof(ttl));
      if (ttl >= 0 && ttl <= 255) metadata[4] = ttl;
    }
  }
#endif
  metadata[0] = (int32_t)ntohl(source.sin_addr.s_addr);
  metadata[1] = (int32_t)ntohs(source.sin_port);
  return (int)count;
}
