#ifndef _L4RE_LIBC_SYS_SIGNALFD_H
#define _L4RE_LIBC_SYS_SIGNALFD_H 1

#include <stdint.h>
#include <signal.h>
#include <sys/types.h>

/* Structure returned by read() on a signalfd */
struct signalfd_siginfo {
    uint32_t ssi_signo;
    int32_t  ssi_errno;
    int32_t  ssi_code;
    uint32_t ssi_pid;
    uint32_t ssi_uid;
    int32_t  ssi_fd;
    uint32_t ssi_tid;
    uint32_t ssi_band;
    uint32_t ssi_overrun;
    uint32_t ssi_trapno;
    int32_t  ssi_status;
    int32_t  ssi_int;
    uint64_t ssi_ptr;
    uint64_t ssi_utime;
    uint64_t ssi_stime;
    uint64_t ssi_addr;
    uint16_t ssi_addr_lsb;
    uint16_t __pad2;
    int32_t  ssi_syscall;
    uint64_t ssi_call_addr;
    uint32_t ssi_arch;
    uint8_t  __pad[28];
};

/* Flags for signalfd */
#define SFD_CLOEXEC  02000000
#define SFD_NONBLOCK 00004000

/* Function prototypes */
int signalfd(int fd, const sigset_t *mask, int flags);
int signalfd4(int fd, const sigset_t *mask, size_t size, int flags);

#endif /* _L4RE_LIBC_SYS_SIGNALFD_H */
