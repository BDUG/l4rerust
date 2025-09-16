use alloc::collections::{BTreeMap, BTreeSet};
use alloc::vec::Vec;
use core::cmp::min;

use super::SchedulerPolicy;

#[cfg(not(test))]
use l4_sys::{l4_cap_idx_t, l4_sched_param_t, run_thread};
#[cfg(test)]
type l4_cap_idx_t = usize;

#[derive(Clone)]
struct Task {
    period: u64,
    base_priority: u64,
    current_priority: u64,
    #[allow(dead_code)]
    thread_cap: l4_cap_idx_t,
    owned_mutexes: BTreeSet<usize>,
}

struct MutexState {
    owner: Option<usize>,
    waiters: Vec<usize>,
}

pub struct AutosarScheduler {
    scheduler_cap: l4_cap_idx_t,
    tasks: BTreeMap<usize, Task>,
    ready: Vec<usize>,
    current: Option<usize>,
    mutexes: BTreeMap<usize, MutexState>,
}

impl AutosarScheduler {
    pub fn new(scheduler_cap: l4_cap_idx_t) -> Self {
        Self {
            scheduler_cap,
            tasks: BTreeMap::new(),
            ready: Vec::new(),
            current: None,
            mutexes: BTreeMap::new(),
        }
    }

    pub fn add_task(&mut self, id: usize, period: u64, thread_cap: l4_cap_idx_t) {
        let task = Task {
            period,
            base_priority: period,
            current_priority: period,
            thread_cap,
            owned_mutexes: BTreeSet::new(),
        };
        self.tasks.insert(id, task);
    }

    fn insert_ready_sorted(&mut self, id: usize) {
        let prio = self.tasks[&id].current_priority;
        let pos = self
            .ready
            .binary_search_by_key(&prio, |tid| self.tasks[tid].current_priority)
            .unwrap_or_else(|e| e);
        self.ready.insert(pos, id);
    }

    pub fn make_ready(&mut self, id: usize) {
        if self.current == Some(id) || self.ready.contains(&id) {
            return;
        }
        self.insert_ready_sorted(id);
        if let Some(cur) = self.current {
            let cur_prio = self.tasks[&cur].current_priority;
            let new_prio = self.tasks[&id].current_priority;
            if new_prio < cur_prio {
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
        if let Some(next_id) = self.ready.first().cloned() {
            self.ready.remove(0);
            self.current = Some(next_id);
            #[cfg(not(test))]
            unsafe {
                run_thread(
                    self.scheduler_cap,
                    self.tasks[&next_id].thread_cap,
                    core::ptr::null_mut::<l4_sched_param_t>(),
                );
            }
        }
    }

    pub fn lock_mutex(&mut self, task: usize, mutex: usize) {
        let m = self.mutexes.entry(mutex).or_insert(MutexState {
            owner: None,
            waiters: Vec::new(),
        });
        if m.owner.is_none() {
            m.owner = Some(task);
            self.tasks
                .get_mut(&task)
                .unwrap()
                .owned_mutexes
                .insert(mutex);
        } else {
            self.ready.retain(|&tid| tid != task);
            let prio = self.tasks[&task].current_priority;
            let pos = m
                .waiters
                .binary_search_by_key(&prio, |tid| self.tasks[tid].current_priority)
                .unwrap_or_else(|e| e);
            m.waiters.insert(pos, task);
            let owner = m.owner.unwrap();
            {
                let owner_task = self.tasks.get_mut(&owner).unwrap();
                owner_task.current_priority = min(owner_task.current_priority, prio);
            }
            if self.ready.contains(&owner) {
                self.ready.retain(|&tid| tid != owner);
                self.insert_ready_sorted(owner);
            }
            if self.current == Some(task) {
                self.current = None;
                self.run_next();
            }
        }
    }

    pub fn unlock_mutex(&mut self, task: usize, mutex: usize) {
        if let Some(m) = self.mutexes.get_mut(&mutex) {
            if m.owner == Some(task) {
                if let Some(next) = m.waiters.first().cloned() {
                    m.waiters.remove(0);
                    m.owner = Some(next);
                    self.tasks
                        .get_mut(&next)
                        .unwrap()
                        .owned_mutexes
                        .insert(mutex);
                    self.make_ready(next);
                } else {
                    m.owner = None;
                }
                self.tasks
                    .get_mut(&task)
                    .unwrap()
                    .owned_mutexes
                    .remove(&mutex);
                let new_prio = self.tasks[&task].owned_mutexes.iter().fold(
                    self.tasks[&task].base_priority,
                    |p, &m_id| {
                        if let Some(mstate) = self.mutexes.get(&m_id) {
                            if let Some(waiter) = mstate.waiters.first() {
                                min(p, self.tasks[waiter].current_priority)
                            } else {
                                p
                            }
                        } else {
                            p
                        }
                    },
                );
                {
                    let t = self.tasks.get_mut(&task).unwrap();
                    t.current_priority = new_prio;
                }
                if self.ready.contains(&task) {
                    self.ready.retain(|&tid| tid != task);
                    self.insert_ready_sorted(task);
                } else if self.current == Some(task) {
                    if let Some(&next_id) = self.ready.first() {
                        let next_prio = self.tasks[&next_id].current_priority;
                        if next_prio < self.tasks[&task].current_priority {
                            self.preempt();
                        }
                    }
                }
            }
        }
    }

    pub fn current_task(&self) -> Option<usize> {
        self.current
    }

    pub fn task_priority(&self, id: usize) -> u64 {
        self.tasks[&id].current_priority
    }
}

impl SchedulerPolicy for AutosarScheduler {
    fn name(&self) -> &'static str {
        "autosar"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn period_based_preemption() {
        let mut s = AutosarScheduler::new(0);
        s.add_task(1, 100, 0); // higher priority
        s.add_task(2, 200, 0); // lower priority
        s.make_ready(2);
        assert_eq!(s.current_task(), Some(2));
        s.make_ready(1);
        assert_eq!(s.current_task(), Some(1));
    }

    #[test]
    fn priority_inheritance() {
        let mut s = AutosarScheduler::new(0);
        s.add_task(1, 200, 0); // low priority
        s.add_task(2, 100, 0); // high priority
        s.make_ready(1);
        s.lock_mutex(1, 1);
        s.make_ready(2);
        s.lock_mutex(2, 1); // blocks and boosts task 1
        assert_eq!(s.current_task(), Some(1));
        assert_eq!(s.task_priority(1), s.task_priority(2));
        s.unlock_mutex(1, 1);
        assert_eq!(s.current_task(), Some(2));
        assert_eq!(s.task_priority(1), 200);
    }
}
