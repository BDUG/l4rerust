PKGDIR ?= .
L4DIR ?= $(PKGDIR)/../..

TARGET := epoll_server

install:: $(TARGET)
	$(INSTALL) -m 755 $(TARGET) $(INSTDIR)/boot/

include $(L4DIR)/mk/subdir.mk
