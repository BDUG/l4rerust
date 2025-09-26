//! L4Re interface crate
//!
//! Reimplemented methods
#![no_std]

#[cfg(target_os = "l4re")]
mod cap;
#[cfg(target_os = "l4re")]
pub mod env;
#[cfg(target_os = "l4re")]
pub mod mem;
#[cfg(target_os = "l4re")]
pub mod sys;

#[cfg(target_os = "l4re")]
pub use cap::OwnedCap;

#[cfg(not(target_os = "l4re"))]
pub struct OwnedCap;
