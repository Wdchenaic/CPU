LOCAL_TOOLCHAIN_MK_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
LOCAL_RISCV_PATH := $(abspath $(LOCAL_TOOLCHAIN_MK_DIR)/../tools/local-riscv-toolchains/current-riscv-none-embed-gcc)

RISCV_GCC     := $(LOCAL_RISCV_PATH)/bin/riscv-none-embed-gcc
RISCV_AS      := $(LOCAL_RISCV_PATH)/bin/riscv-none-embed-as
RISCV_GXX     := $(LOCAL_RISCV_PATH)/bin/riscv-none-embed-g++
RISCV_OBJDUMP := $(LOCAL_RISCV_PATH)/bin/riscv-none-embed-objdump
RISCV_GDB     := $(LOCAL_RISCV_PATH)/bin/riscv-none-embed-gdb
RISCV_AR      := $(LOCAL_RISCV_PATH)/bin/riscv-none-embed-ar
RISCV_OBJCOPY := $(LOCAL_RISCV_PATH)/bin/riscv-none-embed-objcopy
RISCV_READELF := $(LOCAL_RISCV_PATH)/bin/riscv-none-embed-readelf
