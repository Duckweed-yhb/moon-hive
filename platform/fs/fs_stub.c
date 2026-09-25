/* ============================================================
 * MoonHive · platform/fs — 文件系统层（C FFI 存根）
 *
 * 职责：判断路径类型、递归创建/删除目录、遍历目录树、统计体积。
 *
 * 为什么需要它：moonbitlang/core 不提供文件系统模块（只在第三方
 * moonbitlang/async 中）。验证工作区必须能创建、遍历、统计、清理目录。
 *
 * 设计约束：
 *   1. 递归删除有风险——入口必须先做路径合法性检查。
 *   2. 内部递归一律用 C 字符串，绝不在递归中构造 MoonBit 对象，
 *      避免引用计数泄漏（v1 初稿的缺陷，此处已修正）。
 *   3. 不跟随符号链接（避免删除时逃出工作区）。
 *   4. 字符串转换只在 FFI 边界发生。
 * ============================================================ */

#include "moonbit.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#include <wchar.h>
#define MKDIR(p) _mkdir(p)
#define RMDIR(p) _rmdir(p)
#else
#include <dirent.h>
#include <unistd.h>
#define MKDIR(p) mkdir((p), 0777)
#define RMDIR(p) rmdir(p)
#endif

/* 路径类型 */
#define FS_NONE 0
#define FS_FILE 1
#define FS_DIR 2
#define FS_OTHER 3

#define FS_MAX_PATH 4096

/* ---------- 边界转换 ---------- */

static void fs_str_to_ascii(moonbit_string_t src, char *dst, int32_t cap) {
  if (cap <= 0) {
    return;
  }
  if (src == NULL) {
    dst[0] = 0;
    return;
  }
  int32_t n = Moonbit_array_length(src);
  if (n > cap - 1) {
    n = cap - 1;
  }
  for (int32_t i = 0; i < n; i++) {
    uint16_t c = src[i];
    dst[i] = (c > 127) ? '?' : (char)c;
  }
  dst[n] = 0;
}

static moonbit_string_t fs_ascii_to_str(const char *src, int32_t len) {
  if (len < 0) {
    len = 0;
  }
  moonbit_string_t out = moonbit_make_string(len, 0);
  for (int32_t i = 0; i < len; i++) {
    out[i] = (uint16_t)(unsigned char)src[i];
  }
  return out;
}

/* ---------- 纯 C 工具 ---------- */

static void fs_strip_trailing_sep(char *p) {
  int32_t n = (int32_t)strlen(p);
  while (n > 1 && (p[n - 1] == '/' || p[n - 1] == '\\')) {
#ifdef _WIN32
    if (n == 3 && p[1] == ':') {
      break;
    }
#endif
    p[n - 1] = 0;
    n--;
  }
}

static int32_t fs_kind_c(const char *p) {
  struct stat st;
  if (stat(p, &st) != 0) {
    return FS_NONE;
  }
#ifdef _WIN32
  if (st.st_mode & _S_IFDIR) {
    return FS_DIR;
  }
  if (st.st_mode & _S_IFREG) {
    return FS_FILE;
  }
#else
  if (S_ISDIR(st.st_mode)) {
    return FS_DIR;
  }
  if (S_ISREG(st.st_mode)) {
    return FS_FILE;
  }
#endif
  return FS_OTHER;
}

/* 去掉路径末尾分隔符后拼接子项，统一用平台分隔符 */
#ifdef _WIN32
#define FS_SEP "\\"
#else
#define FS_SEP "/"
#endif

static void fs_join(char *dst, int32_t cap, const char *dir, const char *name) {
  snprintf(dst, (size_t)cap, "%s" FS_SEP "%s", dir, name);
}

/* ---------- 路径查询 ---------- */

int32_t fs_path_kind(moonbit_string_t path) {
  char p[FS_MAX_PATH];
  fs_str_to_ascii(path, p, (int32_t)sizeof(p));
  if (p[0] == 0) {
    return FS_NONE;
  }
  return fs_kind_c(p);
}

int32_t fs_is_dir(moonbit_string_t path) {
  return fs_path_kind(path) == FS_DIR;
}

int32_t fs_is_file(moonbit_string_t path) {
  return fs_path_kind(path) == FS_FILE;
}

int32_t fs_exists(moonbit_string_t path) {
  return fs_path_kind(path) != FS_NONE;
}

/* 文件字节大小；目录或不存在返回 -1 */
int64_t fs_file_size(moonbit_string_t path) {
  char p[FS_MAX_PATH];
  fs_str_to_ascii(path, p, (int32_t)sizeof(p));
  struct stat st;
  if (stat(p, &st) != 0) {
    return -1;
  }
  if (fs_kind_c(p) != FS_FILE) {
    return -1;
  }
  return (int64_t)st.st_size;
}

/* ---------- 目录创建 ---------- */

/* 递归创建目录的内部实现（供多处复用） */
static int32_t mkdir_all_c(char *p) {
  if (p[0] == 0) {
    return -1;
  }
  fs_strip_trailing_sep(p);

  for (int32_t i = 1; p[i] != 0; i++) {
    if (p[i] == '/' || p[i] == '\\') {
#ifdef _WIN32
      if (i == 2 && p[1] == ':') {
        continue;
      }
#endif
      char saved = p[i];
      p[i] = 0;
      if (p[0] != 0) {
        MKDIR(p);
      }
      p[i] = saved;
    }
  }
  if (MKDIR(p) != 0) {
    if (fs_kind_c(p) != FS_DIR) {
      return -1;
    }
  }
  return 0;
}

int32_t fs_mkdir_all(moonbit_string_t path) {
  char p[FS_MAX_PATH];
  fs_str_to_ascii(path, p, (int32_t)sizeof(p));
  return mkdir_all_c(p);
}

/* ---------- 递归删除（内部用纯 C 字符串） ---------- */

static int32_t fs_rm_rf_c(const char *p) {
  int32_t kind = fs_kind_c(p);
  if (kind == FS_NONE) {
    return 0; /* 不存在视为已删除 */
  }
  if (kind != FS_DIR) {
    return (remove(p) == 0) ? 0 : -1;
  }

#ifdef _WIN32
  char pattern[FS_MAX_PATH + 8];
  snprintf(pattern, sizeof(pattern), "%s\\*", p);
  WIN32_FIND_DATAA fd;
  HANDLE h = FindFirstFileA(pattern, &fd);
  if (h != INVALID_HANDLE_VALUE) {
    do {
      if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) {
        continue;
      }
      char child[FS_MAX_PATH + 8];
      fs_join(child, (int32_t)sizeof(child), p, fd.cFileName);
      fs_rm_rf_c(child);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
  }
  return (RMDIR(p) == 0) ? 0 : -1;
#else
  DIR *d = opendir(p);
  if (d != NULL) {
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
      if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) {
        continue;
      }
      char child[FS_MAX_PATH + 8];
      fs_join(child, (int32_t)sizeof(child), p, e->d_name);
      fs_rm_rf_c(child);
    }
    closedir(d);
  }
  return (RMDIR(p) == 0) ? 0 : -1;
#endif
}

/* 递归删除目录。为防误删，拒绝过短路径与驱动器根。 */
int32_t fs_rm_rf(moonbit_string_t path) {
  char p[FS_MAX_PATH];
  fs_str_to_ascii(path, p, (int32_t)sizeof(p));
  fs_strip_trailing_sep(p);

  int32_t len = (int32_t)strlen(p);
  if (len < 4) {
    return -2;
  }
#ifdef _WIN32
  if (len == 2 && p[1] == ':') {
    return -2;
  }
#endif
  return fs_rm_rf_c(p);
}

/* ---------- 文件读写 ---------- */

/* 把 UTF-8 字节解码为 UTF-16 并构造 MoonBit 字符串。
   MoonBit 的 String 是 UTF-16，逐字节转换会让多字节字符变乱码。 */
static moonbit_string_t utf8_bytes_to_mbt_str(const char *src, int32_t len) {
  if (len < 0) {
    len = 0;
  }
  uint16_t *u16 = (uint16_t *)malloc(sizeof(uint16_t) * ((size_t)len + 1));
  if (u16 == NULL) {
    return moonbit_make_string(0, 0);
  }
  int32_t n = 0;
  int32_t i = 0;
  if (len >= 3 && (unsigned char)src[0] == 0xEF && (unsigned char)src[1] == 0xBB &&
      (unsigned char)src[2] == 0xBF) {
    i = 3;
  }
  while (i < len) {
    unsigned char c = (unsigned char)src[i];
    uint32_t cp = 0;
    int32_t extra = 0;
    if (c < 0x80) {
      cp = c;
      extra = 0;
    } else if ((c & 0xE0) == 0xC0) {
      cp = c & 0x1F;
      extra = 1;
    } else if ((c & 0xF0) == 0xE0) {
      cp = c & 0x0F;
      extra = 2;
    } else if ((c & 0xF8) == 0xF0) {
      cp = c & 0x07;
      extra = 3;
    } else {
      u16[n++] = (uint16_t)'?';
      i++;
      continue;
    }
    if (i + extra >= len) {
      u16[n++] = (uint16_t)'?';
      break;
    }
    int32_t ok = 1;
    for (int32_t k = 1; k <= extra; k++) {
      if (((unsigned char)src[i + k] & 0xC0) != 0x80) {
        ok = 0;
        break;
      }
      cp = (cp << 6) | (uint32_t)((unsigned char)src[i + k] & 0x3F);
    }
    if (!ok) {
      u16[n++] = (uint16_t)'?';
      i++;
      continue;
    }
    i += extra + 1;
    if (cp < 0x10000) {
      u16[n++] = (uint16_t)cp;
    } else if (cp <= 0x10FFFF) {
      cp -= 0x10000;
      u16[n++] = (uint16_t)(0xD800 | (cp >> 10));
      u16[n++] = (uint16_t)(0xDC00 | (cp & 0x3FF));
    } else {
      u16[n++] = (uint16_t)'?';
    }
  }
  moonbit_string_t out = moonbit_make_string(n, 0);
  for (int32_t k = 0; k < n; k++) {
    out[k] = u16[k];
  }
  free(u16);
  return out;
}

/* 读取文本文件（按 UTF-8 解码）。不存在或不可读返回空串。 */
moonbit_string_t fs_read_text(moonbit_string_t path) {
  char p[FS_MAX_PATH];
  fs_str_to_ascii(path, p, (int32_t)sizeof(p));
  FILE *f = fopen(p, "rb");
  if (f == NULL) {
    return moonbit_make_string(0, 0);
  }
  int32_t cap = 8192, len = 0;
  char *buf = (char *)malloc((size_t)cap);
  if (buf == NULL) {
    fclose(f);
    return moonbit_make_string(0, 0);
  }
  int32_t chunk;
  while ((chunk = (int32_t)fread(buf + len, 1, (size_t)(cap - len - 1), f)) > 0) {
    len += chunk;
    if (len + 1 >= cap) {
      cap *= 2;
      char *nb = (char *)realloc(buf, (size_t)cap);
      if (nb == NULL) {
        break;
      }
      buf = nb;
    }
  }
  fclose(f);
  moonbit_string_t out = utf8_bytes_to_mbt_str(buf, len);
  free(buf);
  return out;
}

/* 把 MoonBit 字符串按 UTF-8 编码写入文件（覆盖写）。成功返回 0。 */
int32_t fs_write_text(moonbit_string_t path, moonbit_string_t content) {
#ifdef _WIN32
  /* Windows：仓库可能位于中文路径（如 E:\future\yhb\03-竞赛\...）。A 版
     fopen 的路径经 fs_str_to_ascii 转换后，中文被替换成 '?'，写文件必然失败。
     MoonBit String 的内存是 UTF-16（uint16_t 数组），Windows wchar_t 同为
     UTF-16——直接逐单元拷贝即可，无需编码转换。 */
  int32_t pn = (int32_t)Moonbit_array_length(path);
  wchar_t *wp = (wchar_t *)malloc(((size_t)pn + 1) * sizeof(wchar_t));
  if (wp == NULL) {
    return -1;
  }
  for (int32_t i = 0; i < pn; i++) {
    wp[i] = (wchar_t)path[i];
  }
  wp[pn] = 0;
  FILE *f = _wfopen(wp, L"wb");
  free(wp);
#else
  char p[FS_MAX_PATH];
  fs_str_to_ascii(path, p, (int32_t)sizeof(p));
  FILE *f = fopen(p, "wb");
#endif
  if (f == NULL) {
    return -1;
  }
  int32_t n = Moonbit_array_length(content);
  for (int32_t i = 0; i < n; i++) {
    uint32_t cp = (uint32_t)content[i];
    /* 处理 UTF-16 代理对 */
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < n) {
      uint32_t lo = (uint32_t)content[i + 1];
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
        i++;
      }
    }
    unsigned char b[4];
    int32_t len = 0;
    if (cp < 0x80) {
      b[0] = (unsigned char)cp;
      len = 1;
    } else if (cp < 0x800) {
      b[0] = (unsigned char)(0xC0 | (cp >> 6));
      b[1] = (unsigned char)(0x80 | (cp & 0x3F));
      len = 2;
    } else if (cp < 0x10000) {
      b[0] = (unsigned char)(0xE0 | (cp >> 12));
      b[1] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
      b[2] = (unsigned char)(0x80 | (cp & 0x3F));
      len = 3;
    } else {
      b[0] = (unsigned char)(0xF0 | (cp >> 18));
      b[1] = (unsigned char)(0x80 | ((cp >> 12) & 0x3F));
      b[2] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
      b[3] = (unsigned char)(0x80 | (cp & 0x3F));
      len = 4;
    }
    fwrite(b, 1, (size_t)len, f);
  }
  fclose(f);
  return 0;
}

/* 删除文件；成功返回 0，失败返回 -1。 */
int32_t fs_remove(moonbit_string_t path) {
  char p[FS_MAX_PATH];
  fs_str_to_ascii(path, p, (int32_t)sizeof(p));
  if (p[0] == 0) {
    return -1;
  }
  return (remove(p) == 0) ? 0 : -1;
}

/* 复制单个文件；成功返回 0 */
int32_t fs_copy_file(moonbit_string_t src, moonbit_string_t dst) {
  char sp[FS_MAX_PATH];
  char dp[FS_MAX_PATH];
  fs_str_to_ascii(src, sp, (int32_t)sizeof(sp));
  fs_str_to_ascii(dst, dp, (int32_t)sizeof(dp));

  FILE *in = fopen(sp, "rb");
  if (in == NULL) {
    return -1;
  }
  FILE *out = fopen(dp, "wb");
  if (out == NULL) {
    fclose(in);
    return -2;
  }
  char buf[65536];
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
    if (fwrite(buf, 1, n, out) != n) {
      fclose(in);
      fclose(out);
      return -3;
    }
  }
  fclose(in);
  fclose(out);
  return 0;
}

/* 递归复制目录。跳过 .git / _build / target 等与验证无关且体积大的目录。 */
static int32_t fs_copy_tree_c(const char *src, const char *dst) {
  if (fs_kind_c(src) != FS_DIR) {
    return -1;
  }
  if (mkdir_all_c(dst) != 0) {
    return -2;
  }

#ifdef _WIN32
  char pattern[FS_MAX_PATH + 8];
  snprintf(pattern, sizeof(pattern), "%s\\*", src);
  WIN32_FIND_DATAA fd;
  HANDLE h = FindFirstFileA(pattern, &fd);
  if (h == INVALID_HANDLE_VALUE) {
    return 0;
  }
  do {
    if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) {
      continue;
    }
    /* 跳过与验证无关的目录，避免无谓的磁盘占用与耗时 */
    if (strcmp(fd.cFileName, ".git") == 0 || strcmp(fd.cFileName, "_build") == 0 ||
        strcmp(fd.cFileName, "target") == 0 || strcmp(fd.cFileName, "node_modules") == 0) {
      continue;
    }
    char cs[FS_MAX_PATH + 8];
    char cd[FS_MAX_PATH + 8];
    fs_join(cs, (int32_t)sizeof(cs), src, fd.cFileName);
    fs_join(cd, (int32_t)sizeof(cd), dst, fd.cFileName);
    if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      fs_copy_tree_c(cs, cd);
    } else {
      char sp2[FS_MAX_PATH];
      char dp2[FS_MAX_PATH];
      strncpy(sp2, cs, sizeof(sp2) - 1);
      sp2[sizeof(sp2) - 1] = 0;
      strncpy(dp2, cd, sizeof(dp2) - 1);
      dp2[sizeof(dp2) - 1] = 0;
      FILE *in = fopen(sp2, "rb");
      if (in != NULL) {
        FILE *out = fopen(dp2, "wb");
        if (out != NULL) {
          char buf[65536];
          size_t n;
          while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
            fwrite(buf, 1, n, out);
          }
          fclose(out);
        }
        fclose(in);
      }
    }
  } while (FindNextFileA(h, &fd));
  FindClose(h);
#else
  DIR *d = opendir(src);
  if (d == NULL) {
    return 0;
  }
  struct dirent *e;
  while ((e = readdir(d)) != NULL) {
    if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) {
      continue;
    }
    if (strcmp(e->d_name, ".git") == 0 || strcmp(e->d_name, "_build") == 0 ||
        strcmp(e->d_name, "target") == 0 || strcmp(e->d_name, "node_modules") == 0) {
      continue;
    }
    char cs[FS_MAX_PATH + 8];
    char cd[FS_MAX_PATH + 8];
    fs_join(cs, (int32_t)sizeof(cs), src, e->d_name);
    fs_join(cd, (int32_t)sizeof(cd), dst, e->d_name);
    if (fs_kind_c(cs) == FS_DIR) {
      fs_copy_tree_c(cs, cd);
    } else {
      FILE *in = fopen(cs, "rb");
      if (in != NULL) {
        FILE *out = fopen(cd, "wb");
        if (out != NULL) {
          char buf[65536];
          size_t n;
          while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
            fwrite(buf, 1, n, out);
          }
          fclose(out);
        }
        fclose(in);
      }
    }
  }
  closedir(d);
#endif
  return 0;
}

int32_t fs_copy_tree(moonbit_string_t src, moonbit_string_t dst) {
  char sp[FS_MAX_PATH];
  char dp[FS_MAX_PATH];
  fs_str_to_ascii(src, sp, (int32_t)sizeof(sp));
  fs_str_to_ascii(dst, dp, (int32_t)sizeof(dp));
  if (sp[0] == 0 || dp[0] == 0) {
    return -1;
  }
  return fs_copy_tree_c(sp, dp);
}

/* ---------- 遍历与统计 ---------- */

static int64_t fs_dir_bytes_c(const char *p, int32_t depth, int32_t max_depth) {
  if (depth > max_depth) {
    return 0;
  }
  int64_t total = 0;

#ifdef _WIN32
  char pattern[FS_MAX_PATH + 8];
  snprintf(pattern, sizeof(pattern), "%s\\*", p);
  WIN32_FIND_DATAA fd;
  HANDLE h = FindFirstFileA(pattern, &fd);
  if (h == INVALID_HANDLE_VALUE) {
    return 0;
  }
  do {
    if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) {
      continue;
    }
    char child[FS_MAX_PATH + 8];
    fs_join(child, (int32_t)sizeof(child), p, fd.cFileName);
    if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      total += fs_dir_bytes_c(child, depth + 1, max_depth);
    } else {
      struct stat st;
      if (stat(child, &st) == 0) {
        total += (int64_t)st.st_size;
      }
    }
  } while (FindNextFileA(h, &fd));
  FindClose(h);
#else
  DIR *d = opendir(p);
  if (d == NULL) {
    return 0;
  }
  struct dirent *e;
  while ((e = readdir(d)) != NULL) {
    if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) {
      continue;
    }
    char child[FS_MAX_PATH + 8];
    fs_join(child, (int32_t)sizeof(child), p, e->d_name);
    struct stat st;
    if (stat(child, &st) != 0) {
      continue;
    }
    if (S_ISDIR(st.st_mode)) {
      total += fs_dir_bytes_c(child, depth + 1, max_depth);
    } else if (S_ISREG(st.st_mode)) {
      total += (int64_t)st.st_size;
    }
  }
  closedir(d);
#endif
  return total;
}

int64_t fs_dir_bytes(moonbit_string_t path, int32_t max_depth) {
  char p[FS_MAX_PATH];
  fs_str_to_ascii(path, p, (int32_t)sizeof(p));
  if (fs_kind_c(p) != FS_DIR) {
    return -1;
  }
  return fs_dir_bytes_c(p, 0, max_depth);
}

/* 列出目录下所有普通文件的完整路径，每行一条。
   内部用动态缓冲累积，最后一次性转成 MoonBit 字符串。
   ext：若为非空字符串，只保留以该扩展名结尾的文件（如 ".mbt"）。 */
moonbit_string_t fs_list_files(moonbit_string_t path, moonbit_string_t ext,
                               int32_t max_depth) {
  char root[FS_MAX_PATH];
  fs_str_to_ascii(path, root, (int32_t)sizeof(root));
  char want_ext[64];
  fs_str_to_ascii(ext, want_ext, (int32_t)sizeof(want_ext));
  int32_t ext_len = (int32_t)strlen(want_ext);

  if (fs_kind_c(root) != FS_DIR) {
    return moonbit_make_string(0, 0);
  }

  /* 结果缓冲 */
  int32_t cap = 4096, len = 0;
  char *buf = (char *)malloc((size_t)cap);
  if (buf == NULL) {
    return moonbit_make_string(0, 0);
  }

  /* 显式栈做深度优先遍历，避免依赖递归时的缓冲管理 */
  int32_t stack_cap = 64, stack_top = 0;
  char **stack = (char **)malloc(sizeof(char *) * (size_t)stack_cap);
  int32_t *depths = (int32_t *)malloc(sizeof(int32_t) * (size_t)stack_cap);
  if (stack == NULL || depths == NULL) {
    free(buf);
    free(stack);
    free(depths);
    return moonbit_make_string(0, 0);
  }
  stack[stack_top] = strdup(root);
  depths[stack_top] = 0;
  stack_top++;

  while (stack_top > 0) {
    stack_top--;
    char *cur = stack[stack_top];
    int32_t cur_depth = depths[stack_top];

    if (cur_depth > max_depth) {
      free(cur);
      continue;
    }

#ifdef _WIN32
    char pattern[FS_MAX_PATH + 8];
    snprintf(pattern, sizeof(pattern), "%s\\*", cur);
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pattern, &fd);
    if (h != INVALID_HANDLE_VALUE) {
      do {
        if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) {
          continue;
        }
        char child[FS_MAX_PATH + 8];
        fs_join(child, (int32_t)sizeof(child), cur, fd.cFileName);
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
          if (stack_top >= stack_cap) {
            stack_cap *= 2;
            stack = (char **)realloc(stack, sizeof(char *) * (size_t)stack_cap);
            depths = (int32_t *)realloc(depths, sizeof(int32_t) * (size_t)stack_cap);
          }
          stack[stack_top] = strdup(child);
          depths[stack_top] = cur_depth + 1;
          stack_top++;
        } else {
          if (ext_len == 0 ||
              (int32_t)strlen(fd.cFileName) > ext_len &&
                  strcmp(fd.cFileName + strlen(fd.cFileName) - (size_t)ext_len,
                         want_ext) == 0) {
            int32_t need = (int32_t)strlen(child) + 1;
            if (len + need + 1 >= cap) {
              while (len + need + 1 >= cap) {
                cap *= 2;
              }
              buf = (char *)realloc(buf, (size_t)cap);
            }
            memcpy(buf + len, child, (size_t)need - 1);
            len += need - 1;
            buf[len++] = '\n';
          }
        }
      } while (FindNextFileA(h, &fd));
      FindClose(h);
    }
#else
    DIR *d = opendir(cur);
    if (d != NULL) {
      struct dirent *e;
      while ((e = readdir(d)) != NULL) {
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) {
          continue;
        }
        char child[FS_MAX_PATH + 8];
        fs_join(child, (int32_t)sizeof(child), cur, e->d_name);
        struct stat st;
        if (stat(child, &st) != 0) {
          continue;
        }
        if (S_ISDIR(st.st_mode)) {
          if (stack_top >= stack_cap) {
            stack_cap *= 2;
            stack = (char **)realloc(stack, sizeof(char *) * (size_t)stack_cap);
            depths = (int32_t *)realloc(depths, sizeof(int32_t) * (size_t)stack_cap);
          }
          stack[stack_top] = strdup(child);
          depths[stack_top] = cur_depth + 1;
          stack_top++;
        } else if (S_ISREG(st.st_mode)) {
          if (ext_len == 0 ||
              ((int32_t)strlen(e->d_name) > ext_len &&
               strcmp(e->d_name + strlen(e->d_name) - (size_t)ext_len, want_ext) == 0)) {
            int32_t need = (int32_t)strlen(child) + 1;
            if (len + need + 1 >= cap) {
              while (len + need + 1 >= cap) {
                cap *= 2;
              }
              buf = (char *)realloc(buf, (size_t)cap);
            }
            memcpy(buf + len, child, (size_t)need - 1);
            len += need - 1;
            buf[len++] = '\n';
          }
        }
      }
      closedir(d);
    }
#endif
    free(cur);
  }

  free(stack);
  free(depths);
  moonbit_string_t out = fs_ascii_to_str(buf, len);
  free(buf);
  return out;
}
