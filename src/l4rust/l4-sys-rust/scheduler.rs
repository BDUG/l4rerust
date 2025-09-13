use crate::c_api::*;

/// Start execution of `thread` under the given `scheduler` or adjust its
/// scheduling parameters.
pub unsafe fn run_thread(
    scheduler: l4_cap_idx_t,
    thread: l4_cap_idx_t,
    sp: *mut l4_sched_param_t,
) -> l4_msgtag_t {
    l4_scheduler_run_thread_w(scheduler, thread, sp)
}

/// Preempt the currently running thread and switch to `thread`.
///
/// This is a thin wrapper around [`run_thread`] that clarifies intent at the
/// call site.
pub unsafe fn preempt_thread(
    scheduler: l4_cap_idx_t,
    thread: l4_cap_idx_t,
    sp: *mut l4_sched_param_t,
) -> l4_msgtag_t {
    l4_scheduler_run_thread_w(scheduler, thread, sp)
}

/// The granularity defines how many CPUs each bit in map describes. And the
///    offset is the number of the first CPU described by the first bit in the
///    bitmap.
/// \pre offset must be a multiple of 2^granularity.
pub unsafe fn l4_sched_cpu_set(
    offset: l4_umword_t,
    granularity: u8,
    map: l4_umword_t,
) -> l4_sched_cpu_set_t {
    l4_sched_cpu_set_w(offset, granularity, map)
}
