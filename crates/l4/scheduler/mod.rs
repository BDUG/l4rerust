//! Scheduler policy selection and configuration.

#![allow(unused)]

extern crate alloc;

use alloc::boxed::Box;

/// Trait implemented by different scheduler policies.
pub trait SchedulerPolicy {
    /// Return the human readable name of the policy.
    fn name(&self) -> &'static str;
}

/// Supported scheduler implementations.
#[derive(Debug, Clone, Copy)]
pub enum SchedulerKind {
    #[cfg(feature = "autosar")]
    Autosar,
    #[cfg(feature = "linux_like")]
    LinuxLike,
}

impl SchedulerKind {
    /// Try to read the scheduler kind from the `L4_SCHEDULER` environment
    /// variable.
    #[cfg(feature = "std")]
    pub fn from_env() -> Option<Self> {
        let val = std::env::var("L4_SCHEDULER").ok()?;
        Self::from_str(&val)
    }

    /// Parse a scheduler kind from the provided string.
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            #[cfg(feature = "autosar")]
            "autosar" => Some(SchedulerKind::Autosar),
            #[cfg(feature = "linux_like")]
            "linux_like" => Some(SchedulerKind::LinuxLike),
            _ => None,
        }
    }

    /// Instantiate a scheduler policy for the selected kind.
    pub fn create(self) -> Box<dyn SchedulerPolicy> {
        match self {
            #[cfg(feature = "autosar")]
            SchedulerKind::Autosar => Box::new(autosar::AutosarScheduler),
            #[cfg(feature = "linux_like")]
            SchedulerKind::LinuxLike => Box::new(linux_like::LinuxLikeScheduler),
        }
    }
}

/// Convenience helper that picks the scheduler policy from the environment and
/// instantiates it. Returns `None` if the environment variable is not set or
/// contains an unknown value.
#[cfg(feature = "std")]
pub fn from_env() -> Option<Box<dyn SchedulerPolicy>> {
    SchedulerKind::from_env().map(|k| k.create())
}

#[cfg(feature = "autosar")]
mod autosar;

#[cfg(feature = "linux_like")]
mod linux_like;
