#include <aio.h>
#include <errno.h>
#include "ipc.h"
#include "env.h"
#include <l4/sys/ipc.h>
#include <l4/sys/utcb.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define OPCODE_AIO_READ   0
#define OPCODE_AIO_WRITE  1
#define OPCODE_AIO_ERROR  2
#define OPCODE_AIO_RETURN 3
#define OPCODE_AIO_CANCEL 4
#define OPCODE_AIO_SUSPEND 5
#define OPCODE_AIO_FSYNC  6

#define BR_WORDS L4_UTCB_GENERIC_BUFFERS_SIZE
#define BR_DATA_BYTES ((BR_WORDS - 1) * sizeof(l4_umword_t))

struct aio_mapping {
    const struct aiocb *cb;
    unsigned long handle;
    struct aio_mapping *next;
};

static pthread_mutex_t map_lock = PTHREAD_MUTEX_INITIALIZER;
static struct aio_mapping *aio_head = NULL;
static l4_cap_idx_t aio_gate = L4_INVALID_CAP;

static void clear_br(void)
{
    l4_buf_regs_t *br = l4_utcb_br();
    br->br[0] = 0;
}

static struct aio_mapping *find_mapping(const struct aiocb *cb)
{
    struct aio_mapping *cur = aio_head;
    while (cur) {
        if (cur->cb == cb)
            return cur;
        cur = cur->next;
    }
    return NULL;
}

static void insert_mapping(const struct aiocb *cb, unsigned long handle)
{
    struct aio_mapping *node = malloc(sizeof(*node));
    if (!node)
        return;
    node->cb = cb;
    node->handle = handle;
    node->next = aio_head;
    aio_head = node;
}

static unsigned long remove_mapping(const struct aiocb *cb)
{
    struct aio_mapping **pp = &aio_head;
    while (*pp) {
        if ((*pp)->cb == cb) {
            struct aio_mapping *node = *pp;
            unsigned long handle = node->handle;
            *pp = node->next;
            free(node);
            return handle;
        }
        pp = &(*pp)->next;
    }
    return 0;
}

static int ensure_gate(void)
{
    if (!l4_is_invalid_cap(aio_gate))
        return 0;

    l4_cap_idx_t gate = l4re_env_get_cap_w("global_aio");
    if (l4_is_invalid_cap(gate))
        return ENOENT;
    aio_gate = gate;
    return 0;
}

static long ipc_call(unsigned words)
{
    l4_utcb_t *utcb = l4_utcb_w();
    l4_msgtag_t tag = l4_ipc_call_w(aio_gate, utcb, l4_msgtag_w(0, words, 0, 0), L4_IPC_NEVER);
    long err = (long)l4_ipc_error_w(tag, utcb);
    if (err)
        return -EIO;
    return 0;
}

static int submit_request(struct aiocb *cb, int opcode, const void *payload,
                          size_t payload_len, unsigned long extra)
{
    int rc = ensure_gate();
    if (rc)
        return rc;

    size_t struct_len = sizeof(*cb);
    if (struct_len + payload_len > BR_DATA_BYTES)
        return EOVERFLOW;

    l4_msg_regs_t *mr = l4_utcb_mr_w();
    l4_buf_regs_t *br = l4_utcb_br();
    unsigned char *dst = (unsigned char *)(br->br + 1);
    memcpy(dst, cb, struct_len);
    if (payload_len)
        memcpy(dst + struct_len, payload, payload_len);
    br->br[0] = struct_len + payload_len;

    mr->mr[0] = opcode;
    mr->mr[1] = struct_len;
    mr->mr[2] = payload_len;
    mr->mr[3] = extra;

    long status = ipc_call(4);
    if (status < 0) {
        clear_br();
        return -status;
    }

    long long result = (long long)mr->mr[0];
    if (result < 0) {
        clear_br();
        return (int)(-result);
    }

    insert_mapping(cb, (unsigned long)mr->mr[0]);
    clear_br();
    return 0;
}

static int call_simple(int opcode, unsigned long handle, long long *result, unsigned long *aux)
{
    int rc = ensure_gate();
    if (rc)
        return rc;

    l4_msg_regs_t *mr = l4_utcb_mr_w();
    mr->mr[0] = opcode;
    mr->mr[1] = handle;

    long status = ipc_call(2);
    if (status < 0)
        return -status;

    long long value = (long long)mr->mr[0];
    if (value < 0)
        return (int)(-value);

    if (result)
        *result = value;
    if (aux)
        *aux = mr->mr[1];
    return 0;
}

int aio_read(struct aiocb *cb)
{
    if (!cb)
        return errno = EINVAL, -1;

    pthread_mutex_lock(&map_lock);
    int rc = submit_request(cb, OPCODE_AIO_READ, NULL, 0, 0);
    pthread_mutex_unlock(&map_lock);

    if (rc) {
        errno = rc;
        return -1;
    }
    return 0;
}

int aio_write(struct aiocb *cb)
{
    if (!cb)
        return errno = EINVAL, -1;

    pthread_mutex_lock(&map_lock);
    const void *buf = cb->aio_buf;
    size_t len = cb->aio_nbytes;
    int rc = submit_request(cb, OPCODE_AIO_WRITE, buf, len, 0);
    pthread_mutex_unlock(&map_lock);

    if (rc) {
        errno = rc;
        return -1;
    }
    return 0;
}

int aio_fsync(int op, struct aiocb *cb)
{
    if (!cb)
        return errno = EINVAL, -1;

    pthread_mutex_lock(&map_lock);
    int rc = submit_request(cb, OPCODE_AIO_FSYNC, NULL, 0, (unsigned long)op);
    pthread_mutex_unlock(&map_lock);

    if (rc) {
        errno = rc;
        return -1;
    }
    return 0;
}

int aio_error(const struct aiocb *cb)
{
    if (!cb)
        return EINVAL;

    pthread_mutex_lock(&map_lock);
    struct aio_mapping *entry = find_mapping(cb);
    unsigned long handle = entry ? entry->handle : 0;
    pthread_mutex_unlock(&map_lock);

    if (!handle)
        return EINVAL;

    long long value = 0;
    int rc = call_simple(OPCODE_AIO_ERROR, handle, &value, NULL);
    if (rc)
        return rc;
    return (int)value;
}

ssize_t aio_return(struct aiocb *cb)
{
    if (!cb)
        return errno = EINVAL, -1;

    pthread_mutex_lock(&map_lock);
    unsigned long handle = remove_mapping(cb);
    pthread_mutex_unlock(&map_lock);

    if (!handle)
        return errno = EINVAL, -1;

    unsigned long aux = 0;
    long long value = 0;
    int rc = call_simple(OPCODE_AIO_RETURN, handle, &value, &aux);
    if (rc) {
        errno = rc;
        return -1;
    }

    if (aux > 0 && cb->aio_buf) {
        l4_buf_regs_t *br = l4_utcb_br();
        size_t available = br->br[0];
        if (available > aux)
            available = aux;
        memcpy(cb->aio_buf, (unsigned char *)(br->br + 1), available);
    }
    clear_br();
    return (ssize_t)value;
}

int aio_cancel(int fd, struct aiocb *cb)
{
    (void)fd;
    if (!cb)
        return AIO_ALLDONE;

    pthread_mutex_lock(&map_lock);
    unsigned long handle = remove_mapping(cb);
    pthread_mutex_unlock(&map_lock);

    if (!handle)
        return AIO_ALLDONE;

    int rc = call_simple(OPCODE_AIO_CANCEL, handle, NULL, NULL);
    if (rc)
        return rc;
    return AIO_ALLDONE;
}

int aio_suspend(const struct aiocb *const list[], int nent, const struct timespec *ts)
{
    (void)ts;
    if (nent < 0)
        return errno = EINVAL, -1;
    if (!list || nent == 0)
        return 0;

    pthread_mutex_lock(&map_lock);
    size_t count = 0;
    for (int i = 0; i < nent; ++i) {
        if (!list[i])
            continue;
        if (find_mapping(list[i]))
            count++;
    }
    unsigned long *handles = calloc(count ? count : 1, sizeof(unsigned long));
    if (!handles) {
        pthread_mutex_unlock(&map_lock);
        errno = ENOMEM;
        return -1;
    }
    size_t pos = 0;
    for (int i = 0; i < nent; ++i) {
        if (!list[i])
            continue;
        struct aio_mapping *entry = find_mapping(list[i]);
        if (entry)
            handles[pos++] = entry->handle;
    }
    pthread_mutex_unlock(&map_lock);

    int rc = 0;
    if (pos) {
        rc = ensure_gate();
        if (!rc) {
            if (pos * sizeof(unsigned long) > BR_DATA_BYTES)
                rc = EOVERFLOW;
            else {
                l4_buf_regs_t *br = l4_utcb_br();
                memcpy((unsigned char *)(br->br + 1), handles, pos * sizeof(unsigned long));
                br->br[0] = pos * sizeof(unsigned long);
                l4_msg_regs_t *mr = l4_utcb_mr_w();
                mr->mr[0] = OPCODE_AIO_SUSPEND;
                mr->mr[1] = pos;
                long status = ipc_call(2);
                if (status < 0)
                    rc = -status;
                else if ((long long)mr->mr[0] < 0)
                    rc = (int)(-(long long)mr->mr[0]);
                clear_br();
            }
        }
    }
    free(handles);
    if (rc) {
        errno = rc;
        return -1;
    }
    return 0;
}

int lio_listio(int mode, struct aiocb *const list[], int nent, struct sigevent *sig)
{
    (void)sig;
    if (nent < 0)
        return errno = EINVAL, -1;
    if (!list)
        return 0;

    for (int i = 0; i < nent; ++i) {
        struct aiocb *cb = list[i];
        if (!cb)
            continue;
        int rc;
        switch (cb->aio_lio_opcode) {
        case LIO_WRITE:
            rc = aio_write(cb);
            break;
        case LIO_READ:
            rc = aio_read(cb);
            break;
        case LIO_NOP:
            rc = 0;
            break;
        default:
            errno = EINVAL;
            return -1;
        }
        if (rc) {
            return -1;
        }
    }

    if (mode == LIO_WAIT) {
        for (int i = 0; i < nent; ++i) {
            struct aiocb *cb = list[i];
            if (!cb)
                continue;
            while (aio_error(cb) == EINPROGRESS) {
                /* busy wait */
            }
        }
    }
    return 0;
}
