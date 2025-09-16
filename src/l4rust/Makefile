PKGDIR	= .
L4DIR	?= $(PKGDIR)/../..

TARGET = libl4re-wrapper

CRATE_DIRS = \
	../../crates/l4-sys \
	../../crates/l4 \
	../../crates/l4re \
	../../crates/l4_derive \
	../../crates/net-client

.PHONY: $(CRATE_DIRS)

all: $(CRATE_DIRS)

$(CRATE_DIRS): libl4re-wrapper
	$(MAKE) -C $@ $(MAKECMDGOALS)

include $(L4DIR)/mk/subdir.mk
