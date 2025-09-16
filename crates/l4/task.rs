//! L4(Re) Task API

use crate::cap::{Cap, CapIdx, Interface, Untyped};
use crate::error::Result;
use crate::ipc::MsgTag;
use crate::types::UMword;
use crate::utcb::Utcb;
use l4_sys::{
    self,
    l4_addr_t,
    l4_cap_idx_t,
    l4_fpage_t,
    l4_msg_item_consts_t::L4_MAP_ITEM_MAP,
    L4_cap_fpage_rights::L4_CAP_FPAGE_RWSD,
};

/// Task kernel object
/// The `Task` represents a combination of the address spaces provided
/// by the L4Re micro kernel. A task consists of at least a memory address space
/// and an object address space. On IA32 there is also an IO-port address space
/// associated with an L4::Task.
///
/// Task objects are created using the Factory interface.
///
pub struct Task {
    cap: l4_cap_idx_t,
}

impl Task {
    /// Create a task interface from a raw capability selector.
    ///
    /// # Safety
    ///
    /// The caller must ensure that `cap` is a valid task capability.
    pub const unsafe fn new(cap: l4_cap_idx_t) -> Self {
        Task { cap }
    }

    /// Retrieve the capability for the currently running task.
    pub fn current() -> Cap<Task> {
        // SAFETY: Every running task has a valid environment structure.
        unsafe {
            Cap {
                interface: Task::new((*l4_sys::l4re_env()).task),
            }
        }
    }
}
// ToDo: inherits from:
//  public Kobject_t<Task, Kobject, L4_PROTO_TASK,
//                   Type_info::Demand_t<2> >

impl Interface for Task {
    #[inline]
    fn raw(&self) -> CapIdx {
        self.cap
    }
}

impl Task {
    /// Map resources available in the source task to a destination task.
    ///
    /// The sendbase describes an offset within  the receive window of the reciving task and the
    /// flex page contains the capability or memory being transfered.
    ///
    /// This method allows for asynchronous rights delegation from one task to another. It can be
    /// used to share memory as well as to delegate access to objects.
    /// The destination task is the task referenced by the capability invoking map and the receive
    /// window is the whole address space of said task.
    #[inline]
    pub unsafe fn map_u(
        &self,
        dst_task: Cap<Task>,
        snd_fpage: l4_fpage_t,
        snd_base: l4_addr_t,
        u: &mut Utcb,
    ) -> Result<MsgTag> {
        MsgTag::from(l4_sys::l4_task_map_u(
            dst_task.raw(),
            self.cap,
            snd_fpage,
            snd_base,
            u.raw,
        ))
        .result()
    }

    /// See `map_u`
    #[inline]
    pub unsafe fn map(
        &self,
        src_task: Cap<Task>,
        snd_fpage: l4_fpage_t,
        snd_base: l4_addr_t,
    ) -> Result<MsgTag> {
        self.map_u(src_task, snd_fpage, snd_base, &mut Utcb::current())
    }

    /// See `unmap`
    #[inline]
    pub unsafe fn unmap_u(
        &self,
        fpage: l4_fpage_t,
        map_mask: UMword,
        u: &mut Utcb,
    ) -> Result<MsgTag> {
        MsgTag::from(l4_sys::l4_task_unmap_u(
            self.cap,
            fpage,
            map_mask as u64,
            u.raw,
        ))
        .result()
    }

    /// Revoke rights from the task.
    ///
    /// This method allows to revoke rights from the destination task and from all the tasks that
    /// got the rights delegated from that task (i.e., this operation does a recursive rights
    /// revocation). The flex page argument has to describe a reference a resource of *this* task.
    ///
    /// If the capability possesses delete rights or if it is the last capability pointing to
    /// the object, calling this function might
    ///       destroy the object itself.
    #[inline]
    pub unsafe fn unmap(&self, fpage: l4_fpage_t, map_mask: UMword) -> Result<MsgTag> {
        self.unmap_u(fpage, map_mask, &mut Utcb::current())
    }

    /// Revoke rights from a task.
    ///
    /// This method allows to revoke rights from the destination task and from all the tasks that
    /// got the rights delegated from that task (i.e., this operation does a recursive rights
    /// revocation). The given flex pages need to be present in this task.
    ///
    /// The caller needs to take care that `num_fpages` is not bigger than
    /// `L4_UTCB_GENERIC_DATA_SIZE - 2`.
    ///
    /// If the capability possesses delete rights or if it is the last capability pointing to the
    /// object, calling this function might destroy the object itself.
    #[inline]
    pub unsafe fn unmap_batch(
        &self,
        fpages: &mut l4_fpage_t,
        num_fpages: usize,
        map_mask: UMword,
        utcb: &Utcb,
    ) -> Result<MsgTag> {
        MsgTag::from(l4_sys::l4_task_unmap_batch_u(
            self.cap,
            fpages,
            num_fpages as u32,
            map_mask as u64,
            utcb.raw,
        ))
        .result()
    }

    /// Release capability and delete object.
    ///
    /// The object will be deleted if the `obj` has sufficient rights. No error will be reported if
    /// the rights are insufficient, however, the capability is removed in all cases.
    #[inline]
    pub unsafe fn delete_obj<T: Interface>(&self, obj: Cap<T>, utcb: &Utcb) -> Result<MsgTag> {
        MsgTag::from(l4_sys::l4_task_delete_obj_u(self.cap, obj.raw(), utcb.raw)).result()
    }

    /// Release capability.
    ///
    /// This operation unmaps the capability from `this` task.
    #[inline]
    pub unsafe fn release_cap<T: Interface>(&self, cap: Cap<T>, u: &Utcb) -> Result<MsgTag> {
        MsgTag::from(l4_sys::l4_task_release_cap_u(self.cap, cap.raw(), u.raw)).result()
    }

    /// Check whether a capability is present (refers to an object).
    ///
    /// A capability is considered present when it refers to an existing kernel object.
    pub fn cap_valid<T: Interface>(&self, cap: &Cap<T>, utcb: &Utcb) -> Result<bool> {
        let tag: Result<MsgTag> = unsafe {
            MsgTag::from(l4_sys::l4_task_cap_valid_u(self.cap, cap.raw(), utcb.raw)).result()
        };
        let tag: MsgTag = tag?;
        Ok(tag.label() > 0)
    }

    /// Check capability equality across task boundaries
    ///
    /// Test whether two capabilities point to the same object with the same rights. The UTCB is
    /// that one of the calling thread.
    pub fn cap_equal<T: Interface>(
        &self,
        cap_a: &Cap<T>,
        cap_b: &Cap<T>,
        utcb: &Utcb,
    ) -> Result<bool> {
        let tag: Result<MsgTag> = unsafe {
            MsgTag::from(l4_sys::l4_task_cap_equal_u(
                self.cap,
                cap_a.raw(),
                cap_b.raw(),
                utcb.raw,
            ))
            .result()
        };
        let tag: MsgTag = tag?;
        Ok(tag.label() == 1)
    }

    /// Add kernel-user memory.
    ///
    /// This adds user-kernel memory (to be used for instance as UTCB) by specifying it in the
    /// given flex page.
    pub unsafe fn add_ku_mem(&self, fpage: l4_fpage_t, utcb: &Utcb) -> Result<MsgTag> {
        MsgTag::from(l4_sys::l4_task_add_ku_mem_u(self.cap, fpage, utcb.raw)).result()
    }
    /// Create a new L4 task.
    ///
    /// The new task's capability and the parent's task capability are mapped into the
    /// child's object space so the task can reference itself and its creator.
    pub unsafe fn create_from(
        mut task_cap: Cap<Untyped>,
        utcb_area: l4_fpage_t,
    ) -> Result<Task> {
        MsgTag::from(l4_sys::l4_factory_create_task(
            (*l4_sys::l4re_env()).factory,
            &mut task_cap.raw(),
            utcb_area,
        ))
        .result()?;

        let current = Task::current();

        MsgTag::from(l4_sys::l4_task_map(
            task_cap.raw(),
            current.raw(),
            l4_sys::l4_obj_fpage(task_cap.raw(), 0, L4_CAP_FPAGE_RWSD as u8),
            l4_sys::l4_map_obj_control(task_cap.raw(), L4_MAP_ITEM_MAP),
        ))
        .result()?;

        MsgTag::from(l4_sys::l4_task_map(
            task_cap.raw(),
            current.raw(),
            l4_sys::l4_obj_fpage(current.raw(), 0, L4_CAP_FPAGE_RWSD as u8),
            l4_sys::l4_map_obj_control(current.raw(), L4_MAP_ITEM_MAP),
        ))
        .result()?;

        Ok(unsafe { Task::new(task_cap.raw()) })
    }
}
