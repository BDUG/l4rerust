//! C type definitions, useful if no libc (crate) support is yet available.
//! If libc is available, definitions will be used from there.
#![allow(non_snake_case)]
#![allow(non_camel_case_types)]

pub use libc::*;

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::{align_of, size_of};

    #[test]
    fn c_types_match_l4re_headers() {
        assert_eq!(size_of::<c_uchar>(), 1);
        assert_eq!(align_of::<c_uchar>(), 1);

        assert_eq!(size_of::<c_char>(), 1);
        assert_eq!(align_of::<c_char>(), 1);

        assert_eq!(size_of::<c_schar>(), 1);
        assert_eq!(align_of::<c_schar>(), 1);

        assert_eq!(size_of::<c_short>(), 2);
        assert_eq!(align_of::<c_short>(), 2);

        assert_eq!(size_of::<c_ushort>(), 2);
        assert_eq!(align_of::<c_ushort>(), 2);

        assert_eq!(size_of::<c_int>(), 4);
        assert_eq!(align_of::<c_int>(), 4);

        assert_eq!(size_of::<c_uint>(), 4);
        assert_eq!(align_of::<c_uint>(), 4);

        assert_eq!(size_of::<c_long>(), 8);
        assert_eq!(align_of::<c_long>(), 8);

        assert_eq!(size_of::<c_ulong>(), 8);
        assert_eq!(align_of::<c_ulong>(), 8);

        assert_eq!(size_of::<c_longlong>(), 8);
        assert_eq!(align_of::<c_longlong>(), 8);

        assert_eq!(size_of::<c_ulonglong>(), 8);
        assert_eq!(align_of::<c_ulonglong>(), 8);
    }
}

