PKGDIR ?= .
L4DIR ?= $(PKGDIR)/../..

TARGET := net_server

install:: $(TARGET)
	$(INSTALL) -m 755 $(TARGET) $(INSTDIR)/boot/

include $(L4DIR)/mk/subdir.mk
