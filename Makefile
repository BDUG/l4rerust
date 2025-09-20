all:
	@if [ -d obj ]; then                                           \
	  $(MAKE) systemd-image;                                       \
	else                                                           \
	  echo "Call 'gmake setup' once for initial setup." ;           \
	  exit 1;                                                      \
	fi

clean:
	@scripts/setup.sh clean

setup:
	@if [ -d obj ]; then                                                            \
          echo "Snapshot has already been setup. Proceed with 'gmake setup' or 'gmake clean'.";    \
	else                                                                            \
	  export PATH=$$(pwd)/bin:$$PATH;                                               \
	  chmod +x scripts/setup.sh;     							\
	  scripts/setup.sh config || exit 1;                                           		\
	  scripts/setup.sh setup || exit 1;                                                      \
	  echo ====================================================================;    \
	  echo ;                                                                        \
          echo Your L4Re tree is set up now. Type 'gmake' to build the tree. This;       \
	  echo will take some time \(depending on the speed of your host system, of;    \
	  echo course\).;                                                               \
	  echo ;                                                                        \
	  echo Boot-images for ARM targets will be placed into obj/l4/arm-*/images.;    \
	  echo Boot-images for MIPS targets will be placed into obj/l4/mips32/images.;    \
	  echo Check obj/l4/.../conf/Makeconf.boot for path configuration during image builds.; \
	  echo ;                                                                        \
	fi

build_all: build_fiasco build_l4re build_images

#.NOTPARALLEL: build_fiasco build_l4re build_images build_all

build_fiasco: $(addsuffix /fiasco,$(wildcard obj/fiasco/*))
build_l4re: $(addsuffix /l4defs.mk.inc,$(wildcard obj/l4/*))

$(addsuffix /fiasco,$(wildcard obj/fiasco/*)):
	$(MAKE) -C $(@D)

$(addsuffix /l4defs.mk.inc,$(wildcard obj/l4/*)):
	$(MAKE) -C $(@D)

build_images: build_l4re build_fiasco
	@echo "=============== Building Images ==============================="
	export PATH=$$(pwd)/bin:$$PATH;                                        \
	[ -e obj/.config ] && . obj/.config;                                   \
	for d in obj/l4/*; do                                                  \
	  if [ -d "$$d" -a -e $$d/.imagebuilds ]; then                         \
	    cat $$d/.imagebuilds | while read args; do                         \
	      $(MAKE) -C $$d uimage $$args;                                    \
	    done;                                                              \
	  fi;                                                                  \
	done	
	@echo "=============== Build done ===================================="

BASH_ARCHES := arm arm64

bash-image: $(addprefix obj/bash/,$(addsuffix /bash,$(BASH_ARCHES))) build_images

obj/bash/%/bash:
	@if [ -z "$$BUILD_SH_INVOKED" ]; then \
		scripts/build.sh --no-clean; \
	else \
		echo "BUILD_SH_INVOKED set; skipping scripts/build.sh for $@"; \
	fi

SYSTEMD_ARCHES := arm arm64
SYSTEMD_OUTPUTS := $(addprefix out/systemd/,$(addsuffix /lib/systemd/systemd,$(SYSTEMD_ARCHES)))

systemd-image: systemd-external $(SYSTEMD_OUTPUTS) build_images

$(SYSTEMD_OUTPUTS): systemd-external
	@if [ ! -f "$@" ]; then \
		echo "Missing expected systemd binary $@ after external build"; \
		exit 1; \
	fi

systemd-external:
	@if [ -z "$$BUILD_SH_INVOKED" ]; then \
		scripts/build.sh --no-clean; \
	else \
		echo "BUILD_SH_INVOKED set; skipping scripts/build.sh for $@"; \
	fi

EXAMPLE_CRATES := \
src/fs_server \
src/net_server \
src/driver_server \
src/examples/driver_client

examples:
	@for crate in $(EXAMPLE_CRATES); do \
		echo "Building $$crate"; \
		cargo build --manifest-path $$crate/Cargo.toml --release; \
	done

gen_prebuilt: copy_prebuilt pre-built-images/l4image

copy_prebuilt2:
	@echo "Creating pre-built image directory"
	@cd obj/l4;                                          \
	for arch in *; do                                    \
	  for i in $$arch/images/*; do \
	      if [ -d $$i ]; then \
		pt=$${i#$$arch/images/}; \
		mkdir -p ../../pre-built-images/$$arch/$$pt; \
		for f in $$i/*.elf $$i/*.uimage; do \
		  cp $$f ../../pre-built-images/$$arch/$$pt; \
		done; \
	      fi; \
	  done; \
	done

copy_prebuilt:
	@echo "Creating pre-built image directory"
	@cd obj/l4;                                          \
	for arch in *; do                                    \
	  mkdir -p ../../pre-built-images/$$arch;            \
	  for i in $$arch/images/*.elf                       \
	           $$arch/images/*.uimage; do                \
	    [ -e $$i ] || continue;                          \
	    if [ $$i != $$arch/images/bootstrap.elf -a       \
	         $$i != $$arch/images/bootstrap.uimage ]; then \
	      cp $$i ../../pre-built-images/$$arch;          \
	    fi;                                              \
	  done;                                              \
	done

pre-built-images/l4image:
	@echo Creating $@
	@src/l4/tool/bin/l4image --create-l4image-binary $@

%:
        @:

help:
	@echo "Targets:"
	@echo "  systemd-image (default) Build image with systemd"
	@echo "  all                      Alias for systemd-image"
	@echo "  setup                    Prepare the source tree"
	@echo "  gen_prebuilt             Generate pre-built images"
	@echo "  bash-image               Build image with Bash as first program"
	@echo "  examples                 Build Rust example servers and clients"
.PHONY: setup all build_all clean help \
build_images build_fiasco build_l4re bash-image \
systemd-image systemd-external examples
