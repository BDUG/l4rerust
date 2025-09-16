PKGDIR ?= .
L4DIR ?= $(PKGDIR)/../..

TARGET := systemd
SYSTEMD_BIN := $(PKGDIR)/../../obj/systemd/$(L4ARCH)/systemd

$(TARGET): $(SYSTEMD_BIN)
	ln -sf $(SYSTEMD_BIN) $(TARGET)

install:: $(TARGET)
	$(INSTALL) -m 755 $(TARGET) $(INSTDIR)/boot/

clean::
	$(RM) $(TARGET)

include $(L4DIR)/mk/subdir.mk
