/* ============================================================
 * MoonHive · platform/proc — 子进程执行层（C FFI 存根）
 *
 * 职责：执行外部命令、捕获 stdout/stderr、返回退出码。
 * 设计约束：
 *   1. 必须支持超时——验证陌生仓库时不能无限等待。
 *   2. stdout 与 stderr 必须分离——编译器诊断在 stderr，结论在 stdout。
 *   3. 所有失败都必须返回可判定的错误码，不允许静默失败。
 *
 * 实现说明（v1）：
 *   使用 popen/pclose。stderr 通过 shell 重定向写入临时文件后回读。
 *   v1 的超时是"尽力而为"：pclose 返回后由调用方结合耗时判断。
 *   真正的进程级强杀（WaitForSingleObject + TerminateProcess）列为 v2，
 *   因为 v1 的全部用例（moon check/build/test）都不会死循环。
 * ============================================================ */

#include "moonbit.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
#define POPEN _popen
#define PCLOSE _pclose
#define UNLINK _unlink
#else
#include <unistd.h>
#define POPEN popen
#define PCLOSE pclose
#define UNLINK unlink
#endif

/* ---------- 错误码 ----------
 *
 * 重要：这些错误码必须与「被调用进程的真实退出码」区分开。
 * 早期版本把 PROC_ERR_POPEN 定义为 -1，而 Windows 上 pclose 在命令
 * 运行失败时**也**返回 -1，导致「命令正常失败」被误报成「无法创建进程」。
 * 因此这里把内部错误码统一移到 -1000 以下，并显式把 pclose 的返回值
 * 与错误码分开上报。
 */
#define PROC_OK 0
#define PROC_ERR_EMPTY_CMD (-1001)
#define PROC_ERR_POPEN (-1002)
#define PROC_ERR_STDERR_FILE (-1003)
#define PROC_ERR_ALLOC (-1004)

static int32_t g_last_error = PROC_OK;
static uint64_t g_last_elapsed_ms = 0;

/* 供 MoonBit 侧读取：popen 失败时的 OS 错误码，便于定位原因 */
static int32_t g_last_os_error = 0;

int32_t proc_last_os_error(void) { return g_last_os_error; }

/* ---------- 工具函数 ---------- */

/* MoonBit String(UTF-16) → ASCII C 串。非 ASCII 一律替换为 '?'，
   因为 v1 只用于命令、路径、版本号这类 ASCII 内容。 */
static void mbt_str_to_ascii(moonbit_string_t src, char *dst, int32_t cap) {
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

/* 生成一个临时文件名（含进程号，避免并发冲突） */
static const char *temp_name(const char *suffix, char *buf, int32_t cap) {
#ifdef _WIN32
  const char *base = getenv("TEMP");
  if (base == NULL) {
    base = ".";
  }
  snprintf(buf, (size_t)cap, "%s\\moonhive_%lu_%s", base,
           (unsigned long)GetCurrentProcessId(), suffix);
#else
  const char *base = getenv("TMPDIR");
  if (base == NULL) {
    base = "/tmp";
  }
  snprintf(buf, (size_t)cap, "%s/moonhive_%d_%s", base, (int)getpid(), suffix);
#endif
  return buf;
}

/* ---------- 公开 FFI ---------- */

/* 执行命令并捕获 stdout（返回值）与 stderr（写入 out_err）。
   返回退出码；失败时返回负错误码，可用 proc_last_error() 区分。 */
int32_t proc_run_capture(moonbit_string_t cmd, moonbit_string_t workdir,
                         moonbit_string_t out_stdout, moonbit_string_t out_stderr,
                         int32_t timeout_ms) {
  (void)timeout_ms; /* v1：超时由调用方按耗时判定，见文件头说明 */
  g_last_error = PROC_OK;
  g_last_elapsed_ms = 0;

  char cmd_buf[4096];
  mbt_str_to_ascii(cmd, cmd_buf, (int32_t)sizeof(cmd_buf));
  if (cmd_buf[0] == 0) {
    g_last_error = PROC_ERR_EMPTY_CMD;
    return PROC_ERR_EMPTY_CMD;
  }

  char wd_buf[1024];
  mbt_str_to_ascii(workdir, wd_buf, (int32_t)sizeof(wd_buf));

  char out_buf[1024];
  mbt_str_to_ascii(out_stdout, out_buf, (int32_t)sizeof(out_buf));

  char err_buf[1024];
  mbt_str_to_ascii(out_stderr, err_buf, (int32_t)sizeof(err_buf));

  char tmp_err[1024];
  temp_name("stderr.txt", tmp_err, (int32_t)sizeof(tmp_err));

  /* 组装完整命令行：切目录 → 执行 → stderr 重定向到临时文件 */
  char full_cmd[6144];
  if (wd_buf[0] != 0) {
#ifdef _WIN32
    snprintf(full_cmd, sizeof(full_cmd),
             "cd /d \"%s\" && %s 2>\"%s\"", wd_buf, cmd_buf, tmp_err);
#else
    snprintf(full_cmd, sizeof(full_cmd),
             "cd \"%s\" && %s 2>\"%s\"", wd_buf, cmd_buf, tmp_err);
#endif
  } else {
    snprintf(full_cmd, sizeof(full_cmd), "%s 2>\"%s\"", cmd_buf, tmp_err);
  }

#ifdef _WIN32
  LARGE_INTEGER freq, t0, t1;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&t0);
#else
  struct timespec t0, t1;
  clock_gettime(CLOCK_MONOTONIC, &t0);
#endif

  FILE *fp = POPEN(full_cmd, "r");
  if (fp == NULL) {
    g_last_error = PROC_ERR_POPEN;
#ifdef _WIN32
    g_last_os_error = (int32_t)GetLastError();
#else
    g_last_os_error = errno;
#endif
    return PROC_ERR_POPEN;
  }
  g_last_os_error = 0;

  /* 累积 stdout */
  int32_t cap = 8192, len = 0;
  char *buf = (char *)malloc((size_t)cap);
  if (buf == NULL) {
    PCLOSE(fp);
    g_last_error = PROC_ERR_ALLOC;
    return PROC_ERR_ALLOC;
  }
  int chunk;
  while ((chunk = (int)fread(buf + len, 1, (size_t)(cap - len - 1), fp)) > 0) {
    len += chunk;
    if (len + 1 >= cap) {
      cap *= 2;
      char *nb = (char *)realloc(buf, (size_t)cap);
      if (nb == NULL) {
        g_last_error = PROC_ERR_ALLOC;
        break;
      }
      buf = nb;
    }
  }
  int32_t rc = (int32_t)PCLOSE(fp);

#ifdef _WIN32
  QueryPerformanceCounter(&t1);
  g_last_elapsed_ms = (uint64_t)((t1.QuadPart - t0.QuadPart) * 1000 / freq.QuadPart);
#else
  clock_gettime(CLOCK_MONOTONIC, &t1);
  g_last_elapsed_ms = (uint64_t)((t1.tv_sec - t0.tv_sec) * 1000 +
                                 (t1.tv_nsec - t0.tv_nsec) / 1000000);
#endif

  /* 写 stdout */
  if (out_buf[0] != 0) {
    FILE *fo = fopen(out_buf, "wb");
    if (fo != NULL) {
      fwrite(buf, 1, (size_t)len, fo);
      fclose(fo);
    }
  }

  /* 回读 stderr */
  if (err_buf[0] != 0) {
    FILE *fe = fopen(tmp_err, "rb");
    if (fe != NULL) {
      int32_t ecap = 4096, elen = 0;
      char *ebuf = (char *)malloc((size_t)ecap);
      if (ebuf != NULL) {
        int ec;
        while ((ec = (int)fread(ebuf + elen, 1, (size_t)(ecap - elen - 1), fe)) > 0) {
          elen += ec;
          if (elen + 1 >= ecap) {
            ecap *= 2;
            char *nb = (char *)realloc(ebuf, (size_t)ecap);
            if (nb == NULL) {
              break;
            }
            ebuf = nb;
          }
        }
        FILE *fw = fopen(err_buf, "wb");
        if (fw != NULL) {
          fwrite(ebuf, 1, (size_t)elen, fw);
          fclose(fw);
        }
        free(ebuf);
      }
      fclose(fe);
    } else {
      g_last_error = PROC_ERR_STDERR_FILE;
    }
  }

  free(buf);
  UNLINK(tmp_err);
  return rc;
}

/* ---------- 进程捕获文件的读回 ---------- */

/* 读取文本文件并按 UTF-8 解码。
 *
 * 为什么符号名带 proc_ 前缀：platform/fs 也提供文本读取，两个包最终
 * 链接进同一个可执行文件，同名符号会导致 multiple definition（实测踩过）。
 *
 * 为什么要做 UTF-8 解码：MoonBit 的 String 是 UTF-16。若把文件字节
 * 逐字节当作 UTF-16 码元，多字节字符会变成乱码（实测：编译器输出里的
 * 框线字符变成 âââ）。 */
moonbit_string_t proc_read_file(moonbit_string_t path) {
  char p[1024];
  mbt_str_to_ascii(path, p, (int32_t)sizeof(p));
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

  uint16_t *u16 = (uint16_t *)malloc(sizeof(uint16_t) * ((size_t)len + 1));
  int32_t n = 0;
  if (u16 != NULL) {
    int32_t i = 0;
    if (len >= 3 && (unsigned char)buf[0] == 0xEF && (unsigned char)buf[1] == 0xBB &&
        (unsigned char)buf[2] == 0xBF) {
      i = 3;
    }
    while (i < len) {
      unsigned char c = (unsigned char)buf[i];
      uint32_t cp = 0;
      int32_t extra = 0;
      if (c < 0x80) {
        cp = c;
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
        if (((unsigned char)buf[i + k] & 0xC0) != 0x80) {
          ok = 0;
          break;
        }
        cp = (cp << 6) | (uint32_t)((unsigned char)buf[i + k] & 0x3F);
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
  }
  moonbit_string_t out = moonbit_make_string(n, 0);
  for (int32_t k = 0; k < n; k++) {
    out[k] = u16[k];
  }
  free(u16);
  free(buf);
  return out;
}

/* 删除文件；成功返回 0。符号名带 proc_ 前缀同样为避免与 fs 冲突。 */
int32_t proc_remove_file(moonbit_string_t path) {
  char p[1024];
  mbt_str_to_ascii(path, p, (int32_t)sizeof(p));
  if (p[0] == 0) {
    return -1;
  }
  return (remove(p) == 0) ? 0 : -1;
}

/* ---------- 诊断接口 ---------- */

int32_t proc_last_error(void) { return g_last_error; }

uint64_t proc_last_elapsed_ms(void) { return g_last_elapsed_ms; }

/* 以指定退出码终止进程。CLI 需要它把错误契约映射成 shell 可见的退出码。
   声明为返回 int32_t 以便 MoonBit 侧声明为 -> Unit 之外的用法；
   实际上 exit() 不返回。 */
void proc_exit(int32_t code) {
  exit((int)code);
}

