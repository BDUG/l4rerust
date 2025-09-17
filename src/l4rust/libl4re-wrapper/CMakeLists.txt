add_library(libl4re-wrapper INTERFACE)

target_include_directories(libl4re-wrapper INTERFACE
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:include>
)
