/************************************************************************************************************************
TPU 控制寄存器定义(接口头文件)
@brief  TPU 控制面 AXI-Lite/MMIO 寄存器地址和位定义
@date   2026/04/16
************************************************************************************************************************/

#include <stdint.h>

#ifndef __TPU_REGS_H
#define __TPU_REGS_H

#define TPU_CTRL_BASEADDR           0x40004000u
#define TPU_CTRL_BASEADDE           TPU_CTRL_BASEADDR

#define TPU_REG_CTRL                0x00u
#define TPU_REG_STATUS              0x04u
#define TPU_REG_MODE                0x08u
#define TPU_REG_NET_ID              0x0Cu
#define TPU_REG_DESC_LO             0x10u
#define TPU_REG_DESC_HI             0x14u
#define TPU_REG_PERF_CYCLE          0x18u

#define TPU_CTRL_START_MASK         0x00000001u
#define TPU_CTRL_SOFT_RESET_MASK    0x00000002u
#define TPU_CTRL_IRQ_EN_MASK        0x00000004u

#define TPU_STATUS_BUSY_MASK        0x00000001u
#define TPU_STATUS_DONE_MASK        0x00000002u
#define TPU_STATUS_ERROR_MASK       0x00000004u

#define TPU_MODE_INFER              0x00000000u

#endif
