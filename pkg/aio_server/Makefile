PKGDIR ?= .
L4DIR ?= $(PKGDIR)/../..

TARGET := aio_server

install:: $(TARGET)
$(INSTALL) -m 755 $(TARGET) $(INSTDIR)/boot/

include $(L4DIR)/mk/subdir.mk
