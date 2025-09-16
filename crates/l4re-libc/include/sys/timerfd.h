#ifndef _L4RE_LIBC_SYS_TIMERFD_H
#define _L4RE_LIBC_SYS_TIMERFD_H 1

#include <time.h>
#include <sys/types.h>

/* Flags for timerfd_create */
#define TFD_CLOEXEC   02000000
#define TFD_NONBLOCK  00004000

/* Flags for timerfd_settime */
#define TFD_TIMER_ABSTIME       1
#define TFD_TIMER_CANCEL_ON_SET 2

/* Function prototypes */
int timerfd_create(int clockid, int flags);
int timerfd_settime(int fd, int flags,
                    const struct itimerspec *new_value,
                    struct itimerspec *old_value);
int timerfd_gettime(int fd, struct itimerspec *curr_value);

#endif /* _L4RE_LIBC_SYS_TIMERFD_H */
