RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow

TARGET = load_misalign_exception

CFLAGS += -D CPU_FREQ_MHZ=50
LDFLAGS += -Wl,--allow-multiple-definition
LINKER_SCRIPT := ./link_tb.lds

C_SRCS := $(wildcard *.c)

COMMON_DIR = ../..
TOOLCHAIN_DIR = ../../..
include ../../common.mk
