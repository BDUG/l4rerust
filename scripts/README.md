# Scripts

This directory hosts helper scripts for building and running the project.

`l4re.config` provides the canonical L4Re `.config` used for non-interactive builds. Copy this file to `obj/.config` before invoking `setup` to avoid interactive prompts when running unattended. The configuration can also be sourced directly; default cross-compilation prefixes for 32-bit ARM and 64-bit ARM are provided but can be overridden by exporting `CROSS_COMPILE_ARM` or `CROSS_COMPILE_ARM64` in the environment prior to sourcing.
