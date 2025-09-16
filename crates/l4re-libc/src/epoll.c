#include "sys/epoll.h"
#include <sys/syscall.h>
#include <unistd.h>

int epoll_create(int size)
{
    (void)size;
    return epoll_create1(0);
}

int epoll_create1(int flags)
{
    return (int)syscall(SYS_epoll_create1, flags);
}

int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event)
{
    return (int)syscall(SYS_epoll_ctl, epfd, op, fd, event);
}

int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout)
{
#ifdef SYS_epoll_wait
    return (int)syscall(SYS_epoll_wait, epfd, events, maxevents, timeout);
#else
    return (int)syscall(SYS_epoll_pwait, epfd, events, maxevents, timeout, NULL, 0);
#endif
}

int epoll_pwait(int epfd, struct epoll_event *events, int maxevents, int timeout,
                const sigset_t *sigmask)
{
    return (int)syscall(SYS_epoll_pwait, epfd, events, maxevents, timeout, sigmask,
                        sizeof(sigset_t));
}
