//! All syscalls provided by Fiasco

use crate::{
    cap::{Cap, Interface},
    ipc::MsgTag,
    sys::l4_timeout_t,
    utcb::Utcb,
};

extern "C" {
    fn l4_ipc_call_wrapper(
        dest: l4_sys::l4_cap_idx_t,
        utcb: *mut l4_sys::l4_utcb_t,
        tag: l4_sys::l4_msgtag_t,
        timeout: l4_sys::l4_timeout_t,
    ) -> l4_sys::l4_msgtag_t;

    fn l4_ipc_receive_wrapper(
        object: l4_sys::l4_cap_idx_t,
        utcb: *mut l4_sys::l4_utcb_t,
        timeout: l4_sys::l4_timeout_t,
    ) -> l4_sys::l4_msgtag_t;

    fn l4_ipc_sleep_wrapper(timeout: l4_sys::l4_timeout_t) -> l4_sys::l4_msgtag_t;
}

/// Simple IPC Call
///
/// Call to given destination and block for answer.
#[inline(always)]
pub fn call<T: Interface>(
    dest: &Cap<T>,
    utcb: &mut Utcb,
    tag: MsgTag,
    timeout: l4_timeout_t,
) -> MsgTag {
    unsafe {
        MsgTag::from(l4_ipc_call_wrapper(
            dest.raw(),
            utcb.raw,
            tag.raw(),
            timeout,
        ))
    }
}

#[inline(always)]
pub fn receive<T: Interface>(object: Cap<T>, utcb: &mut Utcb, timeout: l4_timeout_t) -> MsgTag {
    MsgTag::from(unsafe { l4_ipc_receive_wrapper(object.raw(), utcb.raw, timeout) })
}

/// Sleep for the specified amount of time.
///
/// This submits a blocking IPC to an invalid destination with the timeout being the time to sleep.
#[inline]
pub fn sleep(timeout: l4_timeout_t) -> MsgTag {
    unsafe { MsgTag::from(l4_ipc_sleep_wrapper(timeout)) }
}
