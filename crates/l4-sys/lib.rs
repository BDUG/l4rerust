#![no_std]

#[cfg(target_os = "l4re")]
#[cfg(not(any(target_arch = "aarch64", target_arch = "arm")))]
compile_error!("Only ARM architectures are supported.");

#[cfg(target_os = "l4re")]
#[macro_use]
mod ipc_ext;
#[cfg(target_os = "l4re")]
mod c_api;
#[cfg(target_os = "l4re")]
mod cap;
#[cfg(target_os = "l4re")]
pub mod consts;
#[cfg(target_os = "l4re")]
mod factory;
#[cfg(target_os = "l4re")]
pub mod helpers;
#[cfg(target_os = "l4re")]
mod ipc_basic;
#[cfg(target_os = "l4re")]
mod platform;
#[cfg(target_os = "l4re")]
mod scheduler;
#[cfg(target_os = "l4re")]
mod task;

#[cfg(target_os = "l4re")]
pub use crate::c_api::*;
#[cfg(target_os = "l4re")]
/// expose public C API
pub use crate::cap::*;
#[cfg(target_os = "l4re")]
pub use crate::factory::*;
#[cfg(target_os = "l4re")]
pub use crate::ipc_basic::*;
#[cfg(target_os = "l4re")]
pub use crate::ipc_ext::*;
#[cfg(target_os = "l4re")]
pub use crate::platform::*;
#[cfg(target_os = "l4re")]
pub use crate::scheduler::*;
#[cfg(target_os = "l4re")]
pub use crate::task::*;

#[cfg(target_os = "l4re")]
const L4_PAGEMASKU: l4_addr_t = L4_PAGEMASK as l4_addr_t;

#[cfg(target_os = "l4re")]
#[inline]
pub fn trunc_page(address: l4_addr_t) -> l4_addr_t {
    address & L4_PAGEMASKU
}

/// Round address up to the next page.
///
/// The given address is rounded up to the next minimal page boundary. On most architectures this is a 4k
/// page. Check `L4_PAGESIZE` for the minimal page size.
#[cfg(target_os = "l4re")]
#[inline]
pub fn round_page(address: usize) -> l4_addr_t {
    ((address + L4_PAGESIZE as usize - 1usize) & (L4_PAGEMASK as usize)) as l4_addr_t
}

#[cfg(all(target_os = "l4re", target_arch = "aarch64"))]
pub type L4Umword = u64;
#[cfg(all(target_os = "l4re", target_arch = "aarch64"))]
pub type L4Mword = i64;

#[cfg(all(target_os = "l4re", target_arch = "arm"))]
pub type L4Umword = u32;
#[cfg(all(target_os = "l4re", target_arch = "arm"))]
pub type L4Mword = i32;

#[cfg(not(target_os = "l4re"))]
#[allow(non_camel_case_types)]
mod stub {
    pub type l4_addr_t = usize;

    #[inline]
    pub fn trunc_page(address: l4_addr_t) -> l4_addr_t {
        address & !0xfff
    }

    #[inline]
    pub fn round_page(address: usize) -> l4_addr_t {
        address as l4_addr_t
    }
}

#[cfg(not(target_os = "l4re"))]
pub use stub::*;
