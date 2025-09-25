use alloc::collections::BTreeMap;
use alloc::vec::Vec;
use core::cmp::max;

use super::SchedulerPolicy;

#[cfg(not(test))]
use l4_sys::{l4_cap_idx_t, l4_sched_param_t, run_thread};
#[cfg(test)]
type l4_cap_idx_t = usize;

const BASE_SLICE: u64 = 5;

#[derive(Clone)]
struct Task {
    weight: u64,
    vruntime: u64,
    runtime: u64,
    thread_cap: l4_cap_idx_t,
    slice: u64,
    remaining: u64,
}

pub struct LinuxLikeScheduler {
    scheduler_cap: l4_cap_idx_t,
    tasks: BTreeMap<usize, Task>,
    ready: Vec<usize>,
    current: Option<usize>,
}

impl LinuxLikeScheduler {
    pub fn new(scheduler_cap: l4_cap_idx_t) -> Self {
        Self {
            scheduler_cap,
            tasks: BTreeMap::new(),
            ready: Vec::new(),
            current: None,
        }
    }

    pub fn add_task(&mut self, id: usize, weight: u64, thread_cap: l4_cap_idx_t) {
        let slice = BASE_SLICE * weight / 1024;
        let task = Task {
            weight,
            vruntime: 0,
            runtime: 0,
            thread_cap,
            slice,
            remaining: slice,
        };
        self.tasks.insert(id, task);
    }

    fn insert_ready_sorted(&mut self, id: usize) {
        let vr = self.tasks[&id].vruntime;
        let pos = self
            .ready
            .partition_point(|tid| self.tasks[tid].vruntime > vr);
        self.ready.insert(pos, id);
    }

    pub fn make_ready(&mut self, id: usize) {
        if self.current == Some(id) || self.ready.contains(&id) {
            return;
        }
        self.insert_ready_sorted(id);
        if let Some(cur) = self.current {
            if self.tasks[&id].vruntime < self.tasks[&cur].vruntime {
                self.preempt();
            }
        } else {
            self.run_next();
        }
    }

    fn preempt(&mut self) {
        if let Some(cur) = self.current.take() {
            self.insert_ready_sorted(cur);
        }
        self.run_next();
    }

    fn run_next(&mut self) {
        if let Some(next) = self.ready.pop() {
            let task = self.tasks.get_mut(&next).unwrap();
            task.remaining = task.slice;
            self.current = Some(next);
            #[cfg(not(test))]
            unsafe {
                run_thread(
                    self.scheduler_cap,
                    task.thread_cap,
                    core::ptr::null_mut::<l4_sched_param_t>(),
                );
            }
        }
    }

    pub fn tick(&mut self) {
        if let Some(cur) = self.current {
            let t = self.tasks.get_mut(&cur).unwrap();
            t.runtime += 1;
            let inc = max(1, 1024 / t.weight);
            t.vruntime += inc;
            t.remaining -= 1;
            if t.remaining == 0 {
                self.preempt();
            }
        } else {
            self.run_next();
        }
    }

    pub fn task_runtime(&self, id: usize) -> u64 {
        self.tasks[&id].runtime
    }
}

impl SchedulerPolicy for LinuxLikeScheduler {
    fn name(&self) -> &'static str {
        "linux_like"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fairness_between_equal_tasks() {
        let mut s = LinuxLikeScheduler::new(0);
        s.add_task(1, 1024, 0);
        s.add_task(2, 1024, 0);
        s.make_ready(1);
        s.make_ready(2);
        for _ in 0..100 {
            s.tick();
        }
        let r1 = s.task_runtime(1) as i64;
        let r2 = s.task_runtime(2) as i64;
        assert!((r1 - r2).abs() <= 5);
    }

    #[test]
    fn higher_weight_gets_more_runtime() {
        let mut s = LinuxLikeScheduler::new(0);
        s.add_task(1, 2048, 0); // higher weight
        s.add_task(2, 1024, 0); // baseline
        s.make_ready(1);
        s.make_ready(2);
        for _ in 0..100 {
            s.tick();
        }
        assert!(s.task_runtime(1) > s.task_runtime(2));
    }
}
