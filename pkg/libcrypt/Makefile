SHELL := /bin/bash

PKGDIR ?= .
L4DIR ?= $(PKGDIR)/../..

LIBCRYPT_STAGE_DIR := $(PKGDIR)/../../out/libcrypt/$(L4ARCH)
LIBCRYPT_INCLUDE_DIR := $(LIBCRYPT_STAGE_DIR)/include
LIBCRYPT_LIB_DIR := $(LIBCRYPT_STAGE_DIR)/lib
LIBCRYPT_PKGCONFIG_DIR := $(LIBCRYPT_LIB_DIR)/pkgconfig

install::
	@set -e; \
	if [ -z "$(L4ARCH)" ]; then \
		echo "L4ARCH must be set when installing libcrypt" >&2; \
		exit 1; \
	fi; \
	stage_dir="$(LIBCRYPT_STAGE_DIR)"; \
	if [ ! -d "$$stage_dir" ]; then \
		echo "Missing libcrypt artifacts for $(L4ARCH) at $$stage_dir" >&2; \
		echo "Run scripts/build.sh to produce them before packaging." >&2; \
		exit 1; \
	fi; \
	include_src="$(LIBCRYPT_INCLUDE_DIR)"; \
	lib_src="$(LIBCRYPT_LIB_DIR)"; \
	pkgconfig_src="$(LIBCRYPT_PKGCONFIG_DIR)"; \
	$(INSTALL) -d "$(INSTDIR)/include" "$(INSTDIR)/lib" "$(INSTDIR)/lib/pkgconfig"; \
	if [ -d "$$include_src" ]; then \
		find "$$include_src" -type d -print0 | while IFS= read -r -d '' dir; do \
			rel="$${dir#$$include_src}"; \
			$(INSTALL) -d "$(INSTDIR)/include$$rel"; \
		done; \
		find "$$include_src" -type f -print0 | while IFS= read -r -d '' file; do \
			rel="$${file#$$include_src}"; \
			$(INSTALL) -m 644 "$$file" "$(INSTDIR)/include$$rel"; \
		done; \
		find "$$include_src" -type l -print0 | while IFS= read -r -d '' link; do \
			rel="$${link#$$include_src}"; \
			target="$$(readlink "$$link")"; \
			target_dir="$(INSTDIR)/include$${rel%/*}"; \
			[ -d "$$target_dir" ] || $(INSTALL) -d "$$target_dir"; \
			ln -sf "$$target" "$(INSTDIR)/include$$rel"; \
		done; \
	fi; \
	if [ -d "$$lib_src" ]; then \
		find "$$lib_src" -maxdepth 1 -type f \( -name '*.a' -o -name '*.so' -o -name '*.so.*' \) -print0 | while IFS= read -r -d '' lib; do \
			base="$$(basename "$$lib")"; \
			$(INSTALL) -m 644 "$$lib" "$(INSTDIR)/lib/$$base"; \
		done; \
		find "$$lib_src" -maxdepth 1 -type l \( -name '*.so' -o -name '*.so.*' \) -print0 | while IFS= read -r -d '' solink; do \
			base="$$(basename "$$solink")"; \
			target="$$(readlink "$$solink")"; \
			ln -sf "$$target" "$(INSTDIR)/lib/$$base"; \
		done; \
	fi; \
	if [ -d "$$pkgconfig_src" ]; then \
		find "$$pkgconfig_src" -maxdepth 1 -type f -name '*.pc' -print0 | while IFS= read -r -d '' pc; do \
			base="$$(basename "$$pc")"; \
			$(INSTALL) -m 644 "$$pc" "$(INSTDIR)/lib/pkgconfig/$$base"; \
		done; \
		find "$$pkgconfig_src" -maxdepth 1 -type l -name '*.pc' -print0 | while IFS= read -r -d '' pclink; do \
			base="$$(basename "$$pclink")"; \
			target="$$(readlink "$$pclink")"; \
			ln -sf "$$target" "$(INSTDIR)/lib/pkgconfig/$$base"; \
		done; \
	fi

include $(L4DIR)/mk/subdir.mk
