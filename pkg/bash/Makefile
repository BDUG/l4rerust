PKGDIR ?= .
L4DIR ?= $(PKGDIR)/../..

TARGET := bash

install:: $(TARGET)
	$(INSTALL) -m 755 $(TARGET) $(INSTDIR)/boot/

include $(L4DIR)/mk/subdir.mk

