#include "sys/timerfd.h"
#include <sys/syscall.h>
#include <unistd.h>

int timerfd_create(int clockid, int flags)
{
    return (int)syscall(SYS_timerfd_create, clockid, flags);
}

int timerfd_settime(int fd, int flags,
                    const struct itimerspec *new_value,
                    struct itimerspec *old_value)
{
    return (int)syscall(SYS_timerfd_settime, fd, flags, new_value, old_value);
}

int timerfd_gettime(int fd, struct itimerspec *curr_value)
{
    return (int)syscall(SYS_timerfd_gettime, fd, curr_value);
}
