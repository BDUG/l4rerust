#![allow(dead_code)]

use core::sync::atomic::{AtomicU32, Ordering};
use l4_derive::l4_server;
use crate::l4::ipc::CapProvider; // bring trait for BufferManager::new

// -----------------------------------------------------------------------------
// Minimal stub of the `l4` crate required for the macro expansions
// -----------------------------------------------------------------------------
mod l4 {
    pub mod error {
        pub type Result<T> = core::result::Result<T, ()>;
        #[allow(non_camel_case_types)]
        pub enum GenericErr { MsgTooLong }
    }
    pub mod cap {
        pub type CapIdx = u64;
        pub trait Interface {
            fn raw(&self) -> CapIdx;
        }
    }
    pub mod utcb {
        pub struct UtcbMr;
    }
    pub mod ipc {
        use super::cap::CapIdx;
        use super::error::Result;
        use core::ptr::NonNull;

        pub struct MsgTag;
        pub struct BufferAccess {
            pub ptr: Option<NonNull<CapIdx>>,
        }

        pub trait CapProvider {
            fn new() -> Self
            where
                Self: Sized;
            fn alloc_capslots(&mut self, _d: u8) -> Result<()>;
            unsafe fn access_buffers(&mut self) -> BufferAccess;
        }

        pub trait CapProviderAccess {
            unsafe fn access_buffers(&mut self) -> BufferAccess;
            fn ensure_slots(&mut self, cap_demand: u8) -> Result<()>;
        }

        pub struct BufferManager {
            dummy: CapIdx,
        }

        impl CapProvider for BufferManager {
            fn new() -> Self {
                BufferManager { dummy: 0 }
            }
            fn alloc_capslots(&mut self, _d: u8) -> Result<()> {
                extern "C" {
                    fn l4re_util_cap_alloc() -> u64;
                }
                unsafe {
                    l4re_util_cap_alloc();
                }
                Ok(())
            }
            unsafe fn access_buffers(&mut self) -> BufferAccess {
                BufferAccess { ptr: Some(NonNull::from(&mut self.dummy)) }
            }
        }

        pub mod server {
            pub trait StackBuf {}
            pub trait TypedBuffer<T> {}
        }

        pub mod types {
            use super::{BufferAccess, MsgTag};
            use crate::l4::error::Result;
            use crate::l4::utcb::UtcbMr;

            pub unsafe trait Callable {}
            pub trait Dispatch {
                fn dispatch(&mut self, _: MsgTag, _: &mut UtcbMr, _: &mut BufferAccess) -> Result<MsgTag>;
            }
        }

        pub trait Demand {
            const CAP_DEMAND: u8;
        }

        use core::ffi::c_void;
        pub type Callback = fn(*mut c_void, MsgTag, &mut crate::l4::utcb::UtcbMr, &mut BufferAccess) -> Result<MsgTag>;
        pub fn server_impl_callback<T>(
            _srv: *mut c_void,
            _tag: MsgTag,
            _mr: &mut crate::l4::utcb::UtcbMr,
            _bufs: &mut BufferAccess,
        ) -> Result<MsgTag> {
            unimplemented!()
        }
    }
}

use l4::ipc::{BufferAccess, CapProviderAccess};

// fake capability allocator used by BufferManager::alloc_capslots
static ALLOC_COUNT: AtomicU32 = AtomicU32::new(0);

// The allocator is referenced by our stub BufferManager but we count calls here
#[no_mangle]
pub extern "C" fn l4re_util_cap_alloc() -> u64 {
    ALLOC_COUNT.fetch_add(1, Ordering::SeqCst);
    1
}

// -----------------------------------------------------------------------------
// Trait and server definition
// -----------------------------------------------------------------------------
trait Dummy: CapProviderAccess {
    const PROTOCOL_ID: i64 = 0x4242;
    const CAP_DEMAND: u8 = 1;
    fn op_dispatch(
        &mut self,
        _tag: l4::ipc::MsgTag,
        _mr: &mut l4::utcb::UtcbMr,
        _bufs: &mut BufferAccess,
    ) -> l4::error::Result<l4::ipc::MsgTag> {
        Ok(l4::ipc::MsgTag)
    }
}

#[l4_server(Dummy)]
struct Server {
    __slots: l4::ipc::BufferManager,
}

impl Dummy for Server {}

// -----------------------------------------------------------------------------
// Test
// -----------------------------------------------------------------------------
#[test]
fn server_buffer_access() {
    ALLOC_COUNT.store(0, Ordering::SeqCst);
    let mut s = Server::new(0, l4::ipc::BufferManager::new());
    s.ensure_slots(1).unwrap();
    let access: BufferAccess = unsafe { s.access_buffers() };
    assert!(access.ptr.is_some());
    assert_eq!(ALLOC_COUNT.load(Ordering::SeqCst), 1);
}
