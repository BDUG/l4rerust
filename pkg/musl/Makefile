SHELL := /bin/bash

PKGDIR ?= .
L4DIR ?= $(PKGDIR)/../..

MUSL_STAGE_DIR ?= $(PKGDIR)/../../out/musl/$(L4ARCH)
MUSL_INCLUDE_DIR := $(MUSL_STAGE_DIR)/include
MUSL_LIB_DIR := $(MUSL_STAGE_DIR)/lib
MUSL_PKGCONFIG_DIR := $(MUSL_LIB_DIR)/pkgconfig

install::
@set -euo pipefail; \
if [ -z "$(L4ARCH)" ]; then \
echo "L4ARCH must be set when installing musl" >&2; \
exit 1; \
fi; \
stage_dir="$(MUSL_STAGE_DIR)"; \
if [ ! -d "$$stage_dir" ]; then \
echo "Missing musl artifacts for $(L4ARCH) at $$stage_dir" >&2; \
echo "Run scripts/build.sh to produce them before packaging." >&2; \
exit 1; \
fi; \
include_src="$(MUSL_INCLUDE_DIR)"; \
lib_src="$(MUSL_LIB_DIR)"; \
pkgconfig_src="$(MUSL_PKGCONFIG_DIR)"; \
inst_include="$(INSTDIR)/include"; \
inst_lib="$(INSTDIR)/lib"; \
inst_pkgconfig="$(INSTDIR)/lib/pkgconfig"; \
$(INSTALL) -d "$$inst_include" "$$inst_lib" "$$inst_pkgconfig"; \
copy_tree() { \
local src="$$1" dest="$$2"; \
if [ ! -d "$$src" ]; then \
return 0; \
fi; \
find "$$src" -type d -print0 | while IFS= read -r -d '' dir; do \
rel="$${dir#$$src}"; \
if [ -z "$$rel" ]; then \
continue; \
fi; \
$(INSTALL) -d "$$dest$$rel"; \
done; \
get_mode() { \
python3 - "$$1" <<'PY' \
import os, sys
st = os.stat(sys.argv[1], follow_symlinks=False)
print(oct(st.st_mode & 0o777)[2:])
PY
}; \
find "$$src" -type f -print0 | while IFS= read -r -d '' file; do \
rel="$${file#$$src}"; \
dest_path="$$dest$$rel"; \
dest_dir="$${dest_path%/*}"; \
[ -d "$$dest_dir" ] || $(INSTALL) -d "$$dest_dir"; \
mode="$$(get_mode "$$file")"; \
$(INSTALL) -m "$$mode" "$$file" "$$dest_path"; \
done; \
find "$$src" -type l -print0 | while IFS= read -r -d '' link; do \
rel="$${link#$$src}"; \
dest_path="$$dest$$rel"; \
dest_dir="$${dest_path%/*}"; \
[ -d "$$dest_dir" ] || $(INSTALL) -d "$$dest_dir"; \
target="$$(readlink "$$link")"; \
ln -sf "$$target" "$$dest_path"; \
done; \
}; \
copy_tree "$$include_src" "$$inst_include"; \
copy_tree "$$lib_src" "$$inst_lib"; \
if [ -d "$$pkgconfig_src" ]; then \
copy_tree "$$pkgconfig_src" "$$inst_pkgconfig"; \
fi

include $(L4DIR)/mk/subdir.mk
