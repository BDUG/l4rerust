#include "sys/eventfd.h"
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>

int eventfd(unsigned int initval, int flags)
{
    return (int)syscall(SYS_eventfd2, initval, flags);
}

int eventfd_read(int fd, eventfd_t *value)
{
    ssize_t res = read(fd, value, sizeof(eventfd_t));
    if (res < 0)
        return -1;
    if (res != sizeof(eventfd_t)) {
        errno = EINVAL;
        return -1;
    }
    return 0;
}

int eventfd_write(int fd, eventfd_t value)
{
    ssize_t res = write(fd, &value, sizeof(eventfd_t));
    if (res < 0)
        return -1;
    if (res != sizeof(eventfd_t)) {
        errno = EINVAL;
        return -1;
    }
    return 0;
}
