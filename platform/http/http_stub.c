/* ============================================================
 * MoonHive · platform/http — 本地 HTTP 服务层（C FFI 存根）
 *
 * 职责：在 127.0.0.1 上起一个只服务本地报告目录的 HTTP 服务器，
 *       供浏览器打开 MoonHive 验证仪表盘。
 *
 * 为什么需要它：moonbitlang/core 没有网络模块。web 仪表盘是
 * "软件感"的关键——纯终端在软件大赛里演示吃亏。自建一个最小的
 * 静态服务器，不引第三方库，保持零依赖约束。
 *
 * 设计约束：
 *   1. 只监听 127.0.0.1（回环），不暴露到局域网。
 *   2. 只服务指定根目录下的文件；拒绝路径穿越（..）。
 *   3. 只允许 GET；只做静态文件 + 两个只读 API。
 *   4. 用 W 版 API 处理路径——Windows 上 A 版 API 遇中文路径会
 *      被 fs_str_to_ascii 破坏，这里直接把 UTF-16 转 wchar_t。
 *   5. v1 单线程顺序处理：每个请求毫秒级，静态场景足够。
 *      未来要支持"浏览器触发验证"时，只需把 handle_client 挪到
 *      每连接一个线程，并让验证 job 写进度文件供轮询。
 *
 * Winsock 链接说明：
 *   moon 的 cc-link-flags 只作用于 C 编译，不进入可执行链接
 *   （实测：加了 -lws2_32 后链接仍报 undefined，且会破坏默认
 *   入口导致 WinMain 错误）。因此这里用 LoadLibrary("ws2_32.dll")
 *   在运行时解析符号——ws2_32.dll 在所有 Windows 上都存在，
 *   完全绕开链接器配置，也不引入任何第三方依赖。
 * ============================================================ */

#include "moonbit.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>

/* ---------- 动态加载的 winsock 符号 ---------- */
typedef int(WSAAPI *fn_WSAStartup)(WORD, LPWSADATA);
typedef int(WSAAPI *fn_WSACleanup)(void);
typedef SOCKET(WSAAPI *fn_socket)(int, int, int);
typedef int(WSAAPI *fn_bind)(SOCKET, const struct sockaddr *, int);
typedef int(WSAAPI *fn_listen)(SOCKET, int);
typedef SOCKET(WSAAPI *fn_accept)(SOCKET, struct sockaddr *, int *);
typedef int(WSAAPI *fn_closesocket)(SOCKET);
typedef int(WSAAPI *fn_recv)(SOCKET, char *, int, int);
typedef int(WSAAPI *fn_send)(SOCKET, const char *, int, int);
typedef u_short(WSAAPI *fn_htons)(u_short);
typedef u_long(WSAAPI *fn_htonl)(u_long);
typedef int(WSAAPI *fn_setsockopt)(SOCKET, int, int, const char *, int);

static fn_WSAStartup g_WSAStartup = NULL;
static fn_WSACleanup g_WSACleanup = NULL;
static fn_socket g_socket = NULL;
static fn_bind g_bind = NULL;
static fn_listen g_listen = NULL;
static fn_accept g_accept = NULL;
static fn_closesocket g_closesocket = NULL;
static fn_recv g_recv = NULL;
static fn_send g_send = NULL;
static fn_htons g_htons = NULL;
static fn_htonl g_htonl = NULL;
static fn_setsockopt g_setsockopt = NULL;

/* 一次性加载 ws2_32.dll 并解析全部符号。成功返回 0，失败返回 -1。 */
static int http_ws_init(void) {
  if (g_WSAStartup != NULL) {
    return 0; /* 已初始化 */
  }
  HMODULE m = LoadLibraryA("ws2_32.dll");
  if (m == NULL) {
    return -1;
  }
  g_WSAStartup = (fn_WSAStartup)GetProcAddress(m, "WSAStartup");
  g_WSACleanup = (fn_WSACleanup)GetProcAddress(m, "WSACleanup");
  g_socket = (fn_socket)GetProcAddress(m, "socket");
  g_bind = (fn_bind)GetProcAddress(m, "bind");
  g_listen = (fn_listen)GetProcAddress(m, "listen");
  g_accept = (fn_accept)GetProcAddress(m, "accept");
  g_closesocket = (fn_closesocket)GetProcAddress(m, "closesocket");
  g_recv = (fn_recv)GetProcAddress(m, "recv");
  g_send = (fn_send)GetProcAddress(m, "send");
  g_htons = (fn_htons)GetProcAddress(m, "htons");
  g_htonl = (fn_htonl)GetProcAddress(m, "htonl");
  g_setsockopt = (fn_setsockopt)GetProcAddress(m, "setsockopt");
  if (g_WSAStartup == NULL || g_socket == NULL || g_bind == NULL ||
      g_listen == NULL || g_accept == NULL || g_closesocket == NULL ||
      g_recv == NULL || g_send == NULL || g_htons == NULL || g_htonl == NULL ||
      g_setsockopt == NULL) {
    return -1;
  }
  return 0;
}

/* 辅助宏：把动态符号映射回直观名字 */
#define WSAStartup g_WSAStartup
#define WSACleanup g_WSACleanup
#define socket g_socket
#define bind g_bind
#define listen g_listen
#define accept g_accept
#define closesocket g_closesocket
#define recv g_recv
#define send g_send
#define htons g_htons
#define htonl g_htonl
#define setsockopt g_setsockopt
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <wchar.h>
#define closesocket(fd) close(fd)
#define INVALID_SOCKET (-1)
typedef int SOCKET;
#endif

/* 路径段分隔符：Windows 反斜杠，POSIX 正斜杠 */
#ifdef _WIN32
#define HTTP_SEP '\\'
#else
#define HTTP_SEP '/'
#endif

/* ---------- 错误码 ---------- */
#define HTTP_OK 0
#define HTTP_ERR_WSA (-1001)
#define HTTP_ERR_SOCKET (-1002)
#define HTTP_ERR_BIND (-1003)
#define HTTP_ERR_LISTEN (-1004)
#define HTTP_ERR_ACCEPT (-1005)

#define HTTP_MAX_REQ 8192
#define HTTP_MAX_PATH 4096

/* ---------- 边界转换 ---------- */

/* UTF-16（MoonBit 字符串）→ wchar_t*。Windows wchar_t 为 16 位，可直接复制。 */
static wchar_t *http_utf16_to_wcs(moonbit_string_t s, int32_t *out_len) {
  int32_t n = (s == NULL) ? 0 : Moonbit_array_length(s);
  wchar_t *w = (wchar_t *)malloc(((size_t)n + 1) * sizeof(wchar_t));
  if (w == NULL) {
    return NULL;
  }
  for (int32_t i = 0; i < n; i++) {
    w[i] = (wchar_t)s[i];
  }
  w[n] = 0;
  if (out_len != NULL) {
    *out_len = n;
  }
  return w;
}

/* 全角之外的 ASCII 只用于 URL 解析，直接以单字节处理 */

/* Linux：wchar_t 为 32 位。把（UTF-16 码元放入的）wchar 数组转成 UTF-8
   字节串，供 fopen / opendir 使用。Windows 直接用 W API，不需要它。 */
#ifndef _WIN32
static char *http_wcs_to_utf8(const wchar_t *w) {
  size_t n = wcslen(w);
  char *s = (char *)malloc(n * 4 + 4);
  if (s == NULL) {
    return NULL;
  }
  size_t o = 0;
  for (size_t i = 0; i < n; i++) {
    uint32_t cp = (uint32_t)w[i];
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < n &&
        (uint32_t)w[i + 1] >= 0xDC00 && (uint32_t)w[i + 1] <= 0xDFFF) {
      cp = 0x10000 + ((cp - 0xD800) << 10) + ((uint32_t)w[i + 1] - 0xDC00);
      i++;
      s[o++] = (char)(0xF0 | (cp >> 18));
      s[o++] = (char)(0x80 | ((cp >> 12) & 0x3F));
      s[o++] = (char)(0x80 | ((cp >> 6) & 0x3F));
      s[o++] = (char)(0x80 | (cp & 0x3F));
    } else if (cp < 0x80) {
      s[o++] = (char)cp;
    } else if (cp < 0x800) {
      s[o++] = (char)(0xC0 | (cp >> 6));
      s[o++] = (char)(0x80 | (cp & 0x3F));
    } else {
      s[o++] = (char)(0xE0 | (cp >> 12));
      s[o++] = (char)(0x80 | ((cp >> 6) & 0x3F));
      s[o++] = (char)(0x80 | (cp & 0x3F));
    }
  }
  s[o] = 0;
  return s;
}
#endif

/* ---------- 文件操作（W 版，支持中文路径） ---------- */

static wchar_t *http_join_w(const wchar_t *root, const char *rel) {
  size_t rl = wcslen(root);
  size_t cl = strlen(rel);
  wchar_t *full = (wchar_t *)malloc((rl + cl + 4) * sizeof(wchar_t));
  if (full == NULL) {
    return NULL;
  }
  size_t pos = 0;
  for (size_t i = 0; i < rl; i++) {
    full[pos++] = root[i];
  }
  /* 统一补分隔符 */
  if (pos > 0 && full[pos - 1] != L'\\' && full[pos - 1] != L'/') {
    full[pos++] = (wchar_t)HTTP_SEP;
  }
  for (size_t i = 0; i < cl; i++) {
    full[pos++] = (wchar_t)(unsigned char)rel[i];
  }
  full[pos] = 0;
  return full;
}

/* 读文件到内存，返回 malloc 缓冲（调用方 free）。失败返回 NULL。 */
static char *http_read_file_w(const wchar_t *path, size_t *out_len) {
#ifdef _WIN32
  HANDLE h = CreateFileW(
      path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    return NULL;
  }
  LARGE_INTEGER sz;
  if (!GetFileSizeEx(h, &sz) || sz.QuadPart > (LONGLONG)(16 * 1024 * 1024)) {
    CloseHandle(h);
    return NULL;
  }
  size_t len = (size_t)sz.QuadPart;
  char *buf = (char *)malloc(len + 1);
  if (buf == NULL) {
    CloseHandle(h);
    return NULL;
  }
  DWORD rd = 0;
  BOOL ok = ReadFile(h, buf, (DWORD)len, &rd, NULL);
  CloseHandle(h);
  if (!ok || rd != len) {
    free(buf);
    return NULL;
  }
  buf[len] = 0;
  *out_len = len;
  return buf;
#else
  char *u = http_wcs_to_utf8(path);
  if (u == NULL) {
    return NULL;
  }
  FILE *f = fopen(u, "rb");
  free(u);
  if (f == NULL) {
    return NULL;
  }
  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    return NULL;
  }
  long sz = ftell(f);
  rewind(f);
  if (sz < 0 || sz > (long)(16 * 1024 * 1024)) {
    fclose(f);
    return NULL;
  }
  char *buf = (char *)malloc((size_t)sz + 1);
  if (buf == NULL) {
    fclose(f);
    return NULL;
  }
  size_t rd = fread(buf, 1, (size_t)sz, f);
  fclose(f);
  if (rd != (size_t)sz) {
    free(buf);
    return NULL;
  }
  buf[sz] = 0;
  *out_len = (size_t)sz;
  return buf;
#endif
}

/* 列出根目录下 *.json 报告名，返回 JSON 数组文本。失败返回 NULL。 */
static char *http_list_reports(const wchar_t *root, size_t *out_len) {
#ifdef _WIN32
  size_t rl = wcslen(root);
  wchar_t *pat = (wchar_t *)malloc((rl + 16) * sizeof(wchar_t));
  if (pat == NULL) {
    return NULL;
  }
  wcscpy(pat, root);
  if (rl > 0 && pat[rl - 1] != L'\\' && pat[rl - 1] != L'/') {
    wcscat(pat, L"\\");
  }
  wcscat(pat, L"*.json");

  WIN32_FIND_DATAW fd;
  HANDLE h = FindFirstFileW(pat, &fd);
  free(pat);
  if (h == INVALID_HANDLE_VALUE) {
    char *empty = strdup("[]");
    if (empty != NULL) {
      *out_len = 2;
    }
    return empty;
  }

  /* 累积 JSON：["a.json","b.json",...] */
  size_t cap = 256, len = 0;
  char *buf = (char *)malloc(cap);
  if (buf == NULL) {
    FindClose(h);
    return NULL;
  }
  len += (size_t)snprintf(buf + len, cap - len, "[");
  int first = 1;
  do {
    if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      continue;
    }
    /* 文件名转 UTF-8：wchar_t 逐字符转，非 ASCII 转义为 \uXXXX */
    const wchar_t *wn = fd.cFileName;
    /* 预估：每个 wchar 最多 6 字节（\uXXXX 转义 6 字符） */
    size_t need = (size_t)(2 + 6 * (int)wcslen(wn) + 2);
    if (len + need + 8 >= cap) {
      while (len + need + 8 >= cap) {
        cap *= 2;
      }
      char *nb = (char *)realloc(buf, cap);
      if (nb == NULL) {
        free(buf);
        FindClose(h);
        return NULL;
      }
      buf = nb;
    }
    if (!first) {
      buf[len++] = ',';
    }
    first = 0;
    buf[len++] = '"';
    for (const wchar_t *p = wn; *p; p++) {
      if (*p < 128 && *p != '"' && *p != '\\') {
        buf[len++] = (char)*p;
      } else {
        int32_t n = (int32_t)snprintf(buf + len, cap - len, "\\u%04x", (unsigned)*p);
        if (n > 0) {
          len += (size_t)n;
        }
      }
    }
    buf[len++] = '"';
  } while (FindNextFileW(h, &fd));
  FindClose(h);
  if (len + 2 >= cap) {
    cap *= 2;
    char *nb = (char *)realloc(buf, cap);
    if (nb == NULL) {
      free(buf);
      return NULL;
    }
    buf = nb;
  }
  buf[len++] = ']';
  buf[len] = 0;
  *out_len = len;
  return buf;
#else
  char *u = http_wcs_to_utf8(root);
  if (u == NULL) {
    return NULL;
  }
  DIR *d = opendir(u);
  free(u);
  if (d == NULL) {
    char *empty = strdup("[]");
    if (empty != NULL) {
      *out_len = 2;
    }
    return empty;
  }
  size_t cap = 256, len = 0;
  char *buf = (char *)malloc(cap);
  if (buf == NULL) {
    closedir(d);
    return NULL;
  }
  len += (size_t)snprintf(buf + len, cap - len, "[");
  int first = 1;
  struct dirent *e;
  while ((e = readdir(d)) != NULL) {
    if (e->d_type == DT_DIR) {
      continue;
    }
    size_t nl = strlen(e->d_name);
    if (nl < 5 || strcmp(e->d_name + nl - 5, ".json") != 0) {
      continue;
    }
    /* JSON 字符串转义：控制字符 / 引号 / 反斜杠（UTF-8 字节直接保留） */
    size_t need = 2 + nl * 2 + 2;
    if (len + need + 8 >= cap) {
      while (len + need + 8 >= cap) {
        cap *= 2;
      }
      char *nb = (char *)realloc(buf, cap);
      if (nb == NULL) {
        free(buf);
        closedir(d);
        return NULL;
      }
      buf = nb;
    }
    if (!first) {
      buf[len++] = ',';
    }
    first = 0;
    buf[len++] = '"';
    for (size_t i = 0; i < nl; i++) {
      unsigned char c = (unsigned char)e->d_name[i];
      if (c == '"') {
        buf[len++] = '\\';
        buf[len++] = '"';
      } else if (c == '\\') {
        buf[len++] = '\\';
        buf[len++] = '\\';
      } else if (c < 0x20) {
        int32_t n = (int32_t)snprintf(buf + len, cap - len, "\\u%04x", (unsigned)c);
        if (n > 0) {
          len += (size_t)n;
        }
      } else {
        buf[len++] = (char)c;
      }
    }
    buf[len++] = '"';
  }
  closedir(d);
  if (len + 2 >= cap) {
    cap *= 2;
    char *nb = (char *)realloc(buf, cap);
    if (nb == NULL) {
      free(buf);
      return NULL;
    }
    buf = nb;
  }
  buf[len++] = ']';
  buf[len] = 0;
  *out_len = len;
  return buf;
#endif
}

/* ---------- HTTP 工具 ---------- */

static const char *http_mime_of(const char *path) {
  const char *dot = strrchr(path, '.');
  if (dot == NULL) {
    return "application/octet-stream";
  }
  if (strcmp(dot, ".html") == 0) {
    return "text/html; charset=utf-8";
  }
  if (strcmp(dot, ".css") == 0) {
    return "text/css; charset=utf-8";
  }
  if (strcmp(dot, ".js") == 0) {
    return "application/javascript";
  }
  if (strcmp(dot, ".json") == 0) {
    return "application/json; charset=utf-8";
  }
  if (strcmp(dot, ".svg") == 0) {
    return "image/svg+xml";
  }
  if (strcmp(dot, ".png") == 0) {
    return "image/png";
  }
  if (strcmp(dot, ".md") == 0) {
    return "text/markdown; charset=utf-8";
  }
  return "application/octet-stream";
}

/* URL 百分号解码（原地）。\x00 提前截断。 */
static void http_url_decode(char *s) {
  char *d = s;
  while (*s) {
    if (*s == '%' && s[1] && s[2]) {
      int hi = 0, lo = 0;
      char c1 = s[1], c2 = s[2];
      hi = (c1 >= '0' && c1 <= '9') ? c1 - '0'
          : (c1 >= 'a' && c1 <= 'f') ? c1 - 'a' + 10
          : (c1 >= 'A' && c1 <= 'F') ? c1 - 'A' + 10 : -1;
      lo = (c2 >= '0' && c2 <= '9') ? c2 - '0'
          : (c2 >= 'a' && c2 <= 'f') ? c2 - 'a' + 10
          : (c2 >= 'A' && c2 <= 'F') ? c2 - 'A' + 10 : -1;
      if (hi >= 0 && lo >= 0) {
        *d++ = (char)((hi << 4) | lo);
        s += 3;
        continue;
      }
    }
    *d++ = *s++;
  }
  *d = 0;
}

/* 相对路径规范化：拒绝 .. 、反斜杠、盘符、空。合法返回 0。 */
static int http_normalize_rel(const char *raw, char *out, int32_t cap) {
  if (raw == NULL || raw[0] != '/') {
    return -1;
  }
  const char *p = raw + 1;
  if (*p == 0) {
    return -1; /* 根路径交给 index.html 逻辑 */
  }
  int32_t o = 0;
  while (*p) {
    if (*p == '/' || *p == '\\') {
      p++;
      continue;
    }
    /* 提取一段 */
    const char *seg = p;
    while (*p && *p != '/' && *p != '\\') {
      p++;
    }
    int32_t seg_len = (int32_t)(p - seg);
    if (seg_len == 2 && seg[0] == '.' && seg[1] == '.') {
      return -1; /* 路径穿越，拒绝 */
    }
    if (seg_len == 1 && seg[0] == '.') {
      continue;
    }
    if (o > 0) {
      out[o++] = HTTP_SEP;
    }
    for (int32_t i = 0; i < seg_len && o < cap - 1; i++) {
      out[o++] = seg[i];
    }
  }
  out[o] = 0;
  if (o == 0) {
    return -1;
  }
  return 0;
}

/* 报告名安全校验：只允许 [A-Za-z0-9._-]，禁止 / \ .. */
static int http_safe_name(const char *name) {
  if (name == NULL || name[0] == 0) {
    return -1;
  }
  for (const char *p = name; *p; p++) {
    char c = *p;
    int ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
             (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
    if (!ok) {
      return -1;
    }
  }
  if (strstr(name, "..") != NULL) {
    return -1;
  }
  return 0;
}

static int http_send_all(SOCKET s, const char *buf, int n) {
  int sent = 0;
  while (sent < n) {
    int r = (int)send(s, buf + sent, n - sent, 0);
    if (r <= 0) {
      return -1;
    }
    sent += r;
  }
  return 0;
}

static void http_send_text(SOCKET s, const char *status, const char *ctype,
                           const char *body, size_t len) {
  char head[512];
  int hn = snprintf(head, sizeof(head),
                    "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\n"
                    "Connection: close\r\n\r\n",
                    status, ctype, len);
  if (hn > 0) {
    http_send_all(s, head, hn);
  }
  if (len > 0) {
    http_send_all(s, body, (int)len);
  }
}

/* ---------- 请求处理 ---------- */

static void http_handle_client(SOCKET c, const wchar_t *root) {
  char req[HTTP_MAX_REQ];
  int n = (int)recv(c, req, HTTP_MAX_REQ - 1, 0);
  if (n <= 0) {
    closesocket(c);
    return;
  }
  req[n] = 0;

  char method[16], path[HTTP_MAX_PATH], ver[16];
  if (sscanf(req, "%15s %4095s %15s", method, path, ver) != 3) {
    http_send_text(c, "400 Bad Request", "text/plain", "bad request", 11);
    closesocket(c);
    return;
  }
  if (strcmp(method, "GET") != 0) {
    http_send_text(c, "405 Method Not Allowed", "text/plain", "GET only", 8);
    closesocket(c);
    return;
  }

  /* 分离 query 并解码 */
  char *q = strchr(path, '?');
  if (q != NULL) {
    *q = 0;
  }
  http_url_decode(path);

  /* API：报告列表 */
  if (strcmp(path, "/api/reports") == 0) {
    size_t len = 0;
    char *body = http_list_reports(root, &len);
    if (body == NULL) {
      http_send_text(c, "500 Internal Server Error", "text/plain", "list failed", 11);
    } else {
      http_send_text(c, "200 OK", "application/json; charset=utf-8", body, len);
      free(body);
    }
    closesocket(c);
    return;
  }

  /* API：单个报告 JSON */
  if (strncmp(path, "/api/report/", 12) == 0) {
    const char *name = path + 12;
    if (http_safe_name(name) != 0) {
      http_send_text(c, "403 Forbidden", "text/plain", "forbidden", 9);
      closesocket(c);
      return;
    }
    wchar_t *full = http_join_w(root, name);
    size_t len = 0;
    char *body = (full == NULL) ? NULL : http_read_file_w(full, &len);
    free(full);
    if (body == NULL) {
      http_send_text(c, "404 Not Found", "text/plain", "not found", 9);
    } else {
      http_send_text(c, "200 OK", "application/json; charset=utf-8", body, len);
      free(body);
    }
    closesocket(c);
    return;
  }

  /* 静态文件 */
  char rel[HTTP_MAX_PATH];
  if (strcmp(path, "/") == 0) {
    /* 根路径 → 仪表盘入口 */
    snprintf(rel, sizeof(rel), "%s", "dashboard.html");
  } else if (http_normalize_rel(path, rel, sizeof(rel)) != 0) {
    http_send_text(c, "404 Not Found", "text/plain", "not found", 9);
    closesocket(c);
    return;
  }
  wchar_t *full = http_join_w(root, rel);
  size_t len = 0;
  char *body = (full == NULL) ? NULL : http_read_file_w(full, &len);
  free(full);
  if (body == NULL) {
    http_send_text(c, "404 Not Found", "text/plain", "not found", 9);
  } else {
    http_send_text(c, "200 OK", http_mime_of(rel), body, len);
    free(body);
  }
  closesocket(c);
}

/* ---------- 服务器入口 ---------- */

int32_t http_serve(moonbit_string_t root_s, int32_t port) {
#ifdef _WIN32
  if (http_ws_init() != 0) {
    return HTTP_ERR_WSA;
  }
#endif

  wchar_t *root = http_utf16_to_wcs(root_s, NULL);
  if (root == NULL) {
    return HTTP_ERR_SOCKET;
  }

#ifdef _WIN32
  WSADATA wsa;
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    free(root);
    return HTTP_ERR_WSA;
  }
#endif

  SOCKET ls = socket(AF_INET, SOCK_STREAM, 0);
  if (ls == INVALID_SOCKET) {
    free(root);
    return HTTP_ERR_SOCKET;
  }

  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((unsigned short)port);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  if (bind(ls, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    closesocket(ls);
    free(root);
    return HTTP_ERR_BIND;
  }
  if (listen(ls, 8) != 0) {
    closesocket(ls);
    free(root);
    return HTTP_ERR_LISTEN;
  }

  /* 阻塞服务，直到进程被 Ctrl+C 终止 */
  for (;;) {
    SOCKET c = accept(ls, NULL, NULL);
    if (c == INVALID_SOCKET) {
      closesocket(ls);
      free(root);
      return HTTP_ERR_ACCEPT;
    }
    /* 半开连接防护：接收超时 5 秒。v1 单线程串行处理，若某个客户端
       连上却不发送数据（浏览器预连接、TCP 半开等），阻塞 recv 会把
       整个服务永久卡死，后续请求全部排队——表现为浏览器无限加载。
       设置超时后，这种连接 5 秒被断开，服务自动恢复。 */
#ifdef _WIN32
    DWORD rcvto = 5000;
    setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, (const char *)&rcvto, sizeof(rcvto));
#else
    struct timeval rcvto;
    rcvto.tv_sec = 5;
    rcvto.tv_usec = 0;
    setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &rcvto, sizeof(rcvto));
#endif
    http_handle_client(c, root);
  }
}
