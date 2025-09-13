#include "sys/signalfd.h"
#include <sys/syscall.h>
#include <unistd.h>

int signalfd(int fd, const sigset_t *mask, int flags)
{
    return signalfd4(fd, mask, sizeof(uint64_t), flags);
}

int signalfd4(int fd, const sigset_t *mask, size_t size, int flags)
{
    return (int)syscall(SYS_signalfd4, fd, mask, size, flags);
}
