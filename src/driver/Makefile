CROSS_COMPILE ?= aarch64-linux-gnu-

CC := $(CROSS_COMPILE)g++
CXX := $(CROSS_COMPILE)g++
AR := $(CROSS_COMPILE)ar

all:
	CC=$(CC) \
	CXX=$(CXX) \
	AR=$(AR) \
	CROSS_COMPILE=$(CROSS_COMPILE) \
	cargo build --manifest-path Cargo.toml --release --target aarch64-unknown-linux-gnu

clean:
	cargo clean --manifest-path Cargo.toml

.PHONY: all clean
