#![no_std]
#[cfg(feature = "std")]
extern crate std;

#[cfg(target_os = "l4re")]
#[macro_use]
extern crate bitflags;
#[cfg(target_os = "l4re")]
#[macro_use]
extern crate num_derive;
#[cfg(target_os = "l4re")]
extern crate num_traits;

// apart from macro_use, keep this alphabetical
#[cfg(target_os = "l4re")]
#[macro_use]
pub mod types;
#[cfg(target_os = "l4re")]
#[macro_use]
pub mod error;
#[cfg(target_os = "l4re")]
#[macro_use]
pub mod utcb;
#[cfg(target_os = "l4re")]
pub mod cap;
#[cfg(target_os = "l4re")]
pub mod ipc;
#[cfg(all(target_os = "l4re", not(feature = "std")))]
#[macro_use]
pub mod nostd_helper;
#[cfg(target_os = "l4re")]
pub mod task;

#[cfg(all(target_os = "l4re", feature = "scheduler"))]
pub mod scheduler;

#[cfg(all(target_os = "l4re", feature = "scheduler"))]
pub use scheduler::{SchedulerKind, SchedulerPolicy};

#[cfg(target_os = "l4re")]
pub use crate::error::{Error, Result};
#[cfg(target_os = "l4re")]
pub use crate::utcb::*;

#[cfg(target_os = "l4re")]
pub mod sys {
    pub use l4_sys::*;
}

#[cfg(not(target_os = "l4re"))]
pub mod sys {}

#[cfg(not(target_os = "l4re"))]
pub mod host {
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct Unsupported;

    pub type Error = Unsupported;
    pub type Result<T> = core::result::Result<T, Unsupported>;
}

#[cfg(not(target_os = "l4re"))]
pub use host::{Error, Result};
