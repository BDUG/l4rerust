CROSS_COMPILE ?= $(CROSS_COMPILE_ARM64)
CROSS_COMPILE ?= aarch64-linux-gnu-

all:
	CC=$(CROSS_COMPILE)gcc \
	AR=$(CROSS_COMPILE)ar \
	CROSS_COMPILE=$(CROSS_COMPILE) \
	cargo build --manifest-path Cargo.toml --release --target aarch64-unknown-linux-gnu

clean:
	cargo clean --manifest-path Cargo.toml

.PHONY: all clean
