#include "sys/inotify.h"
#include <sys/syscall.h>
#include <unistd.h>

int inotify_init(void)
{
    return inotify_init1(0);
}

int inotify_init1(int flags)
{
    return (int)syscall(SYS_inotify_init1, flags);
}

int inotify_add_watch(int fd, const char *pathname, uint32_t mask)
{
    return (int)syscall(SYS_inotify_add_watch, fd, pathname, mask);
}

int inotify_rm_watch(int fd, int wd)
{
    return (int)syscall(SYS_inotify_rm_watch, fd, wd);
}
