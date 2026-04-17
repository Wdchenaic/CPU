RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow

TARGET = breath_tpu_soc_demo

TPU_RUNTIME_USE_MMIO ?= 0
BREATH_TPU_SOC_DEMO_USE_UART ?= 1

CFLAGS += -D CPU_FREQ_MHZ=50
CFLAGS += -D TPU_RUNTIME_USE_MMIO=$(TPU_RUNTIME_USE_MMIO)
CFLAGS += -D BREATH_TPU_SOC_DEMO_USE_UART=$(BREATH_TPU_SOC_DEMO_USE_UART)

C_SRCS := $(wildcard *.c)
C_SRCS += ../../lib/tpu_runtime.c
COMMON_DIR = ../..
TOOLCHAIN_DIR = ../../..
include ../../common.mk
include ../../local_toolchain_xpack.mk
