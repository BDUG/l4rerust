#ifndef _L4RE_LIBC_SYS_EVENTFD_H
#define _L4RE_LIBC_SYS_EVENTFD_H 1

#include <stdint.h>
#include <sys/types.h>

typedef uint64_t eventfd_t;

/* Flags for eventfd() */
#define EFD_SEMAPHORE 1
#define EFD_CLOEXEC   02000000
#define EFD_NONBLOCK  00004000

/* Function prototypes */
int eventfd(unsigned int initval, int flags);
int eventfd_read(int fd, eventfd_t *value);
int eventfd_write(int fd, eventfd_t value);

#endif /* _L4RE_LIBC_SYS_EVENTFD_H */
