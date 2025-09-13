/// L4 IPC framework
///
/// The interplay in a component-based microkernel system and the number of interfaces create
/// inherent complexity. This framework assists the application programmer to implement services
/// easily without the need to understand all low-level details. As a plus, clients can be
/// auto-derived from the IPC interface definition shared between client and server.
///
/// # Interface Compatibility
///
/// This interface is binary-compatible with the C++ version. This means that at a few places,
/// compromises had to be made. In turn, this gives Rustic applications to talk to the rest of the
/// world. A certain familiarity with L4 IPC is assumed, terms as gate, label, call, flexpage and
/// UTCB are used frequently.

#[macro_use]
mod iface;
mod serialise;
pub mod server;
pub mod syscall;
pub mod types;

pub use self::serialise::{Serialisable, Serialiser};
pub use self::server::{server_impl_callback, Callback, Loop, LoopBuilder};
pub use self::types::*;
pub use syscall::*;

use core::{convert::From, mem::transmute};
use core::ffi::{c_int, c_long, c_ulong};
use l4_sys::{
    c_api::{
        l4_error_code_t::L4_ENOMEM,
        l4_msg_item_consts_t::{L4_ITEM_CONT, L4_ITEM_MAP},
    },
    consts::UTCB_GENERIC_DATA_SIZE,
    l4_fpage_t, l4_msg_regs_t, l4_msgtag_t, l4_umword_t, l4_utcb_t,
    l4_utcb_mr_u, l4_msgtag_flags::*, msgtag,
};
use l4_sys::cap;
use num_traits::FromPrimitive;

use crate::error::{Error, Result};
use crate::types::{Mword, Protocol, UMword};

use l4_sys;

enumgenerator! {
    /// flags for message tags
    enum MsgTagFlags {
        /// Error indicator flag for a received message.
        L4_MSGTAG_ERROR        => Error,
        /// Enable FPU transfer flag for IPC send.
        ///
        /// By enabling this flag when sending IPC, the sender indicates that the contents of the FPU
        /// shall be transfered to the receiving thread. However, the receiver has to indicate its
        /// willingness to receive FPU context in its buffer descriptor register (BDR).
        L4_MSGTAG_TRANSFER_FPU => TransferFpu,
        /// Enable schedule in IPC flag. (sending)
        ///
        /// Usually IPC operations donate the remaining time slice of a thread to the called thread.
        /// Enabling this flag when sending IPC does a real scheduling decision. However, this flag
        /// decreases IPC performance.
        L4_MSGTAG_SCHEDULE     => Schedule,
        /// Enable IPC propagation.
        /// This flag enables IPC propagation, which means an IPC reply-connection from the current
        /// caller will be propagated to the new IPC receiver. This makes it possible to propagate an
        /// IPC call to a third thread, which may then directly answer to the caller.
        L4_MSGTAG_PROPAGATE    => Propagate,
        /// Mask for all flags.
        L4_MSGTAG_FLAGS        => Mask,
    }
}

const L4_MSGTAG_ERROR_I: isize = L4_MSGTAG_ERROR as isize;

/// Message Tag
///
/// Message tags are used for the communication to instruct the kernel which protocol to use for
/// communication (the label), how many (untyped) words to send, how many typed items to map/grant
/// and which flags to use for these actions.
/// When calling another process, the protocol is passed to the server to identify the protocol in
/// use. During the reply of the service process, the label is used for transmitting error results
/// and negative numbers are reserved for errors.
/// Words and items are counted in machine words (`Mword`).
///
/// # Examples
///
/// ```
/// // Send 2 (machine) words, 0 items, no flags, no protocol
/// let _ = msgtag::new(0, 2, 0, 0);
/// // Send a word and a flex page.
/// // NOTE: flex page also take up space in the message registers, though they are "typed" words
/// // and hence do **not** count as a word, even though they take up the space of two words.
/// let _ = msgtag(0, 1, 1, 0);
/// ```
#[derive(Clone)]
#[repr(transparent)]
pub struct MsgTag {
    raw: Mword,
}

impl MsgTag {
    /// Initialise message tag
    /// Initialise given message tag for IPC with label/protocol, count of words in the message
    /// registers, the numbers of typed items (flex pages, etc.) to transfer and the transfer
    /// flags.
    #[inline]
    pub fn new(label: i64, words: u32, items: u32, flags: u32) -> MsgTag {
        MsgTag {
            // the C type is a wrapper type and we reimplement its creation function in
            // l4_sys::ipc_basic anyway. We want to safe every cycle here.
            raw: msgtag(label, words, items, flags).raw as _,
        }
    }

    /// Get the assigned label
    ///
    /// When sending a message, the label field is used for denoting the protocol type, while it is
    /// used for transmitting a result when receiving a message.
    /// When setting protocols, it is advised to use the safer `protocol()` method.
    #[inline]
    pub fn label(&self) -> i64 {
        (self.raw >> 16) as i64
    }

    /// Get the protocol of the message tag
    ///
    /// This is internally the same as the `label()` function, wrapping the value in a safe
    /// Protocol enum. This only works for L4-predefined (kernel) protocols.
    pub fn protocol(&self) -> Result<Protocol> {
        Protocol::from_isize(self.raw >> 16)
            .ok_or(Error::InvalidArg("Unknown protocol", Some(self.raw >> 16)))
    }

    /// Set the label value.
    ///
    /// The label is a raw number used to identify a protocol when doing a send and usable for
    /// return values when answering a rquest. If a protocol is set, it is advisable to use the
    /// `set_protocol()` method.
    pub fn set_label(&mut self, l: i64) {
        self.raw = (self.raw & 0x0ffff) | ((l as isize) << 16)
    }

    /// Set the protocol of the message tag
    ///
    /// The label of a message tag is used to set the protocol of a message. This function allows
    /// to set one of the predefined protocol values safely.
    pub fn set_protocol(&mut self, p: Protocol) {
        self.raw = (self.raw & 0x0ffff) | ((p as isize) << 16)
    }

    /// Get the number of untyped words.
    #[inline]
    pub fn words(&self) -> UMword {
        (self.raw as UMword) & 0x3f
    }

    /// Get the number of typed items.
    #[inline]
    pub fn items(&self) -> UMword {
        ((self.raw as UMword) >> 6) & 0x3f
    }

    /// Get the flags value.
    ///
    /// The flags are a combination of the flags defined by `l4_msgtag_flags`.
    #[inline]
    pub fn flags(&self) -> u32 {
        (self.raw as u32) & 0xf000
    }

    /// Test if flags indicate an error.
    #[inline(always)]
    pub fn has_error(&self) -> bool {
        (self.raw & L4_MSGTAG_ERROR_I) != 0
    }

    /// Check message tag for errors
    ///
    /// This function is only useful for message tags obtained as return value
    /// of an IPC call. It checks the Thread Control Registers (TCR) for an
    /// error code and afterwards the "label" field. A negative label is by
    /// convention an error and can be freely chosen by the programmer.
    #[inline]
    pub fn result(self) -> Result<MsgTag> {
        if self.has_error() {
            return unsafe {
                Err(Error::from_tag_raw(transmute::<Mword, l4_msgtag_t>(
                    self.raw,
                )))
            };
        }
        if self.label() < 0 {
            return Err(Error::from_ipc(self.label()));
        }
        Ok(self)
    }

    #[inline]
    pub fn raw(self) -> l4_msgtag_t {
        ::l4_sys::l4_msgtag_t {
            raw: self.raw as i64,
        }
    }
}

impl From<l4_msgtag_t> for MsgTag {
    #[inline(always)]
    fn from(input: l4_msgtag_t) -> MsgTag {
        MsgTag {
            raw: input.raw as Mword,
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
// re-implemented inline functions from l4/sys/ipc.h:

#[inline]
pub fn l4_msgtag_flags(t: l4_msgtag_t) -> c_ulong {
    (t.raw & 0xf000) as c_ulong
}

/// Re-implementation returning bool instead of int
#[inline]
pub fn l4_msgtag_has_error(t: l4_msgtag_t) -> bool {
    (t.raw & l4_sys::consts::MSGTAG_ERROR) != 0
}

/// This function's return type is altered in comparison to the orig: c_uint -> usize, return value
/// is used as index and this needs to be usize in Rust world.
#[inline]
pub fn l4_msgtag_items(t: l4_msgtag_t) -> usize {
    ((t.raw >> 6) & 0x3f) as usize
}

#[inline]
pub fn l4_msgtag_label(t: l4_msgtag_t) -> c_long {
    (t.raw >> 16) as c_long
}

#[inline]
pub fn l4_msgtag_words(t: l4_msgtag_t) -> u32 {
    (t.raw & 0x3f) as u32
}

/// Add a flex-page for sending
///
/// This function adds a flex page to the first message register of the UTCB.
/// Additionally, the given message tag is modified by increasing the word count.
/// A return code of 0 denotes success, errors are negative.
#[inline]
pub unsafe fn l4_sndfpage_add_u(
    snd_fpage: l4_fpage_t,
    snd_base: c_ulong,
    tag: *mut l4_msgtag_t,
    utcb: *mut l4_utcb_t,
) -> c_int {
    let i = l4_msgtag_words(*tag) as usize + 2 * l4_msgtag_items(*tag);
    if i >= (UTCB_GENERIC_DATA_SIZE - 1) {
        return (L4_ENOMEM as c_int) * -1;
    }

    let v = l4_utcb_mr_u(utcb);
    (*v).mr[i] = snd_base | L4_ITEM_MAP as u64 | L4_ITEM_CONT as u64;
    (*v).mr[i + 1] = snd_fpage.raw;

    *tag = msgtag(
        l4_msgtag_label(*tag) as i64,
        l4_msgtag_words(*tag),
        l4_msgtag_items(*tag) as u32 + 1,
        l4_msgtag_flags(*tag) as u32,
    );
    0
}

/// See `l4_sndfpage_add_u`
#[inline]
pub unsafe fn l4_sndfpage_add(
    snd_fpage: l4_fpage_t,
    snd_base: c_ulong,
    tag: *mut l4_msgtag_t,
) -> c_int {
    l4_sndfpage_add_u(snd_fpage, snd_base, tag, l4_sys::l4_utcb())
}

/// Create the first word for a map item for the memory space.
#[inline]
pub fn l4_map_control(snd_base: l4_umword_t, cache: u8, grant: u32) -> l4_umword_t {
    cap::l4_map_control(snd_base, cache, grant)
}

// ToDo: broken
//#[inline]
//pub unsafe fn l4_rcv_ep_bind_thread_u(gate: l4_cap_idx_t, thread: l4_cap_idx_t,
//        label: l4_umword_t, utcb: *mut l4_utcb_t) -> l4_msgtag_t {
//    let m: *mut l4_msg_regs_t = l4_utcb_mr_u(utcb);
//    (*m).mr[0] = L4_fpage_control_L4_FPAGE_CONTROL_MASK;
//    (*m).mr[1] = label;
//    (*m).mr[2] = cap::l4_map_obj_control(0, 0);
//    (*m).mr[3] = cap::l4_obj_fpage(thread, 0, cap::FPAGE_RWX).raw;
//    l4_ipc_call(gate, utcb,
//                l4_msgtag(l4_msgtag_protocol_L4_PROTO_KOBJECT as i64, 2, 1, 0),
//                l4_timeout_t { raw: 0 })
//}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use l4_sys::{ipc_ext as c, l4_msgtag_flags};

    #[test]
    fn msgtag_helpers_match_c() {
        let flags = (l4_msgtag_flags::L4_MSGTAG_PROPAGATE as u32)
            | (l4_msgtag_flags::L4_MSGTAG_SCHEDULE as u32);
        let tag = c::msgtag(0x1234, 3, 2, flags);

        assert_eq!(l4_msgtag_flags(tag), c::msgtag_flags(tag) as c_ulong);
        assert_eq!(l4_msgtag_has_error(tag), c::msgtag_has_error(tag));
        assert_eq!(l4_msgtag_items(tag), c::msgtag_items(tag));
        assert_eq!(l4_msgtag_label(tag), c::msgtag_label(tag) as c_long);
        assert_eq!(l4_msgtag_words(tag), c::msgtag_words(tag));
    }

    #[test]
    fn msgtag_has_error_matches_c() {
        let tag = c::msgtag(
            0,
            0,
            0,
            l4_msgtag_flags::L4_MSGTAG_ERROR as u32,
        );
        assert!(l4_msgtag_has_error(tag) == c::msgtag_has_error(tag));
    }

    #[test]
    fn sndfpage_add_u_matches_c() {
        unsafe {
            let mut utcb1 = MaybeUninit::<l4_utcb_t>::zeroed();
            let mut utcb2 = MaybeUninit::<l4_utcb_t>::zeroed();
            let utcb1_ptr = utcb1.as_mut_ptr();
            let utcb2_ptr = utcb2.as_mut_ptr();

            let mut tag1 = c::msgtag(0, 0, 0, 0);
            let mut tag2 = tag1;

            let fpage = l4_fpage_t { raw: 0x1000 };
            let base: c_ulong = 0x2000;

            l4_sndfpage_add_u(fpage, base, &mut tag1, utcb1_ptr);
            c::sndfpage_add_u(fpage, base, &mut tag2, utcb2_ptr);

            let mr1 = l4_utcb_mr_u(utcb1_ptr);
            let mr2 = l4_utcb_mr_u(utcb2_ptr);

            assert_eq!((*mr1).mr[0], (*mr2).mr[0]);
            assert_eq!((*mr1).mr[1], (*mr2).mr[1]);
            assert_eq!(tag1.raw, tag2.raw);
        }
    }

    static mut CURRENT_UTCB: *mut l4_utcb_t = core::ptr::null_mut();

    #[no_mangle]
    pub extern "C" fn l4_utcb_w() -> *mut l4_utcb_t {
        unsafe { CURRENT_UTCB }
    }

    #[test]
    fn sndfpage_add_matches_c() {
        unsafe {
            let mut utcb1 = MaybeUninit::<l4_utcb_t>::zeroed();
            let mut utcb2 = MaybeUninit::<l4_utcb_t>::zeroed();
            let utcb1_ptr = utcb1.as_mut_ptr();
            let utcb2_ptr = utcb2.as_mut_ptr();

            let mut tag1 = c::msgtag(0, 0, 0, 0);
            let mut tag2 = tag1;

            let fpage = l4_fpage_t { raw: 0x3000 };
            let base: c_ulong = 0x4000;

            CURRENT_UTCB = utcb1_ptr;
            l4_sndfpage_add(fpage, base, &mut tag1);

            CURRENT_UTCB = utcb2_ptr;
            c::sndfpage_add(fpage, base, &mut tag2);

            let mr1 = l4_utcb_mr_u(utcb1_ptr);
            let mr2 = l4_utcb_mr_u(utcb2_ptr);

            assert_eq!((*mr1).mr[0], (*mr2).mr[0]);
            assert_eq!((*mr1).mr[1], (*mr2).mr[1]);
            assert_eq!(tag1.raw, tag2.raw);
        }
    }

    #[test]
    fn map_control_matches_c() {
        let base: l4_umword_t = 0x1234;
        let cache: u8 = 3;
        let grant: u32 = 1;
        assert_eq!(l4_map_control(base, cache, grant), c::map_control(base, cache, grant));
    }
}
