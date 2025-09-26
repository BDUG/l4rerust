cmake_minimum_required(VERSION 3.20)

project(l4rerust LANGUAGES C CXX)

# Expose a cache variable for the cross-compiler prefix and mirror it into
# the legacy architecture-specific cache entries for backwards compatibility.
set(_l4rerust_cross_default "aarch64-linux-gnu-")
if(DEFINED ENV{CROSS_COMPILE} AND NOT "$ENV{CROSS_COMPILE}" STREQUAL "")
  set(_l4rerust_cross_value "$ENV{CROSS_COMPILE}")
elseif(DEFINED ENV{CROSS_COMPILE_ARM64} AND NOT "$ENV{CROSS_COMPILE_ARM64}" STREQUAL "")
  set(_l4rerust_cross_value "$ENV{CROSS_COMPILE_ARM64}")
elseif(DEFINED ENV{CROSS_COMPILE_ARM} AND NOT "$ENV{CROSS_COMPILE_ARM}" STREQUAL "")
  set(_l4rerust_cross_value "$ENV{CROSS_COMPILE_ARM}")
else()
  set(_l4rerust_cross_value "${_l4rerust_cross_default}")
endif()

set(CROSS_COMPILE
    "${_l4rerust_cross_value}"
    CACHE STRING "Cross-compiler prefix shared across all architectures.")

set(_l4rerust_cross_arm_default "arm-linux-gnueabihf-")
if(DEFINED ENV{CROSS_COMPILE_ARM} AND NOT "$ENV{CROSS_COMPILE_ARM}" STREQUAL "")
  set(_l4rerust_cross_arm_value "$ENV{CROSS_COMPILE_ARM}")
elseif(NOT "${CROSS_COMPILE}" STREQUAL "")
  set(_l4rerust_cross_arm_value "${CROSS_COMPILE}")
else()
  set(_l4rerust_cross_arm_value "${_l4rerust_cross_arm_default}")
endif()
set(CROSS_COMPILE_ARM
    "${_l4rerust_cross_arm_value}"
    CACHE INTERNAL "Derived from CROSS_COMPILE for legacy consumers.")

if(DEFINED ENV{CROSS_COMPILE_ARM64} AND NOT "$ENV{CROSS_COMPILE_ARM64}" STREQUAL "")
  set(_l4rerust_cross_arm64_value "$ENV{CROSS_COMPILE_ARM64}")
else()
  set(_l4rerust_cross_arm64_value "${CROSS_COMPILE}")
endif()
set(CROSS_COMPILE_ARM64
    "${_l4rerust_cross_arm64_value}"
    CACHE INTERNAL "Derived from CROSS_COMPILE for legacy consumers.")

set(_l4rerust_legacy_cross_defaults
    CROSS_COMPILE_MIPS32R2 "mips-linux-"
    CROSS_COMPILE_MIPS32R6 "mips-linux-"
    CROSS_COMPILE_MIPS64R2 "mips-linux-"
    CROSS_COMPILE_MIPS64R6 "mips-linux-"
)

while(_l4rerust_legacy_cross_defaults)
  list(POP_FRONT _l4rerust_legacy_cross_defaults _var)
  list(POP_FRONT _l4rerust_legacy_cross_defaults _default)

  if(DEFINED ENV{${_var}} AND NOT "$ENV{${_var}}" STREQUAL "")
    set(_value "$ENV{${_var}}")
  else()
    set(_value "${_default}")
  endif()

  set(${_var}
      "${_value}"
      CACHE STRING "Cross-compiler prefix (mirrors ${_var}).")
endwhile()

unset(_value)
unset(_var)
unset(_l4rerust_cross_default)
unset(_l4rerust_cross_value)
unset(_l4rerust_cross_arm_default)
unset(_l4rerust_cross_arm_value)
unset(_l4rerust_cross_arm64_value)
unset(_l4rerust_legacy_cross_defaults)

# Location of the upstream l4re-core checkout.
if(DEFINED ENV{L4RE_CORE_DIR} AND NOT "$ENV{L4RE_CORE_DIR}" STREQUAL "")
  set(_l4rerust_l4re_core_default "$ENV{L4RE_CORE_DIR}")
else()
  set(_l4rerust_l4re_core_default "${CMAKE_CURRENT_SOURCE_DIR}/src/l4re-core")
endif()
set(L4RE_CORE_DIR
    "${_l4rerust_l4re_core_default}"
    CACHE PATH "Path to the L4Re core checkout used for headers and libraries."
)
unset(_l4rerust_l4re_core_default)

add_subdirectory(src/l4rust/libl4re-wrapper)
