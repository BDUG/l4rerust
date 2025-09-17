add_library(libl4re-wrapper STATIC
  lib/debug.c
  lib/env.c
  lib/ipc.c
  lib/mem.c
  lib/scheduler.c
)

set_target_properties(libl4re-wrapper PROPERTIES
  OUTPUT_NAME l4re-wrapper
  LINKER_LANGUAGE C
)

target_include_directories(libl4re-wrapper
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

set(_l4re_header_roots
  "${L4RE_CORE_DIR}"
  "${L4RE_CORE_DIR}/l4re"
  "${L4RE_CORE_DIR}/l4sys"
  "${L4RE_CORE_DIR}/l4re_c"
)

set(_l4re_header_paths)

find_path(_l4re_sys_include_dir
  NAMES l4/sys/debugger.h
  HINTS ${_l4re_header_roots}
  PATH_SUFFIXES include include/l4
)
if(_l4re_sys_include_dir)
  list(APPEND _l4re_header_paths "${_l4re_sys_include_dir}")
endif()
unset(_l4re_sys_include_dir)

find_path(_l4re_env_include_dir
  NAMES l4/re/env.h
  HINTS ${_l4re_header_roots}
  PATH_SUFFIXES include include/l4
)
if(_l4re_env_include_dir)
  list(APPEND _l4re_header_paths "${_l4re_env_include_dir}")
endif()
unset(_l4re_env_include_dir)

list(REMOVE_DUPLICATES _l4re_header_paths)

if(_l4re_header_paths)
  target_include_directories(libl4re-wrapper PUBLIC ${_l4re_header_paths})
else()
  message(WARNING
    "Unable to locate L4Re headers under ${L4RE_CORE_DIR}; "
    "builds may fail without <l4/...> include paths.")
endif()
unset(_l4re_header_paths)
unset(_l4re_header_roots)

set(_l4re_library_search_roots "${L4RE_CORE_DIR}")
foreach(_suffix
    lib
    lib32
    lib64
    lib/arm
    lib/aarch64
    lib/amd64
    lib/mips
    lib/mips32
    lib/mips64
    lib/ppc32
    lib/riscv
    lib/riscv64
    lib/x86
  )
  if(EXISTS "${L4RE_CORE_DIR}/${_suffix}")
    list(APPEND _l4re_library_search_roots "${L4RE_CORE_DIR}/${_suffix}")
  endif()
endforeach()

file(GLOB _l4re_candidate_libdirs LIST_DIRECTORIES TRUE
  "${L4RE_CORE_DIR}/lib/*"
  "${L4RE_CORE_DIR}/*/lib"
  "${L4RE_CORE_DIR}/*/lib/*"
)
foreach(_dir IN LISTS _l4re_candidate_libdirs)
  if(IS_DIRECTORY "${_dir}")
    list(APPEND _l4re_library_search_roots "${_dir}")
  endif()
endforeach()
unset(_l4re_candidate_libdirs)
list(REMOVE_DUPLICATES _l4re_library_search_roots)

find_library(L4RE_PTHREAD_LIBRARY
  NAMES pthread-l4 pthread l4pthread
  HINTS ${_l4re_library_search_roots}
)
if(NOT L4RE_PTHREAD_LIBRARY)
  message(FATAL_ERROR "Failed to locate pthread-l4 in ${L4RE_CORE_DIR}")
endif()

find_library(L4RE_C_LIBRARY
  NAMES l4re_c
  HINTS ${_l4re_library_search_roots}
)
if(NOT L4RE_C_LIBRARY)
  message(FATAL_ERROR "Failed to locate l4re_c in ${L4RE_CORE_DIR}")
endif()

find_library(L4RE_C_UTIL_LIBRARY
  NAMES l4re_c-util
  HINTS ${_l4re_library_search_roots}
)
if(NOT L4RE_C_UTIL_LIBRARY)
  message(FATAL_ERROR "Failed to locate l4re_c-util in ${L4RE_CORE_DIR}")
endif()
unset(_l4re_library_search_roots)

target_link_libraries(libl4re-wrapper
  PUBLIC
    ${L4RE_PTHREAD_LIBRARY}
    ${L4RE_C_LIBRARY}
    ${L4RE_C_UTIL_LIBRARY}
)
