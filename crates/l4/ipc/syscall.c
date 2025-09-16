#include <l4/sys/ipc.h>

l4_msgtag_t l4_ipc_call_wrapper(l4_cap_idx_t dest,
                                l4_utcb_t *utcb,
                                l4_msgtag_t tag,
                                l4_timeout_t timeout)
{
    return l4_ipc_call(dest, utcb, tag, timeout);
}

l4_msgtag_t l4_ipc_receive_wrapper(l4_cap_idx_t object,
                                   l4_utcb_t *utcb,
                                   l4_timeout_t timeout)
{
    return l4_ipc_receive(object, utcb, timeout);
}

l4_msgtag_t l4_ipc_sleep_wrapper(l4_timeout_t timeout)
{
    return l4_ipc_sleep(timeout);
}
