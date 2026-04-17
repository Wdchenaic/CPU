#include <stdint.h>
#include "../../include/utils.h"

#define MCAUSE_LOAD_ADDR_MISALIGNED 4u

static volatile uint32_t probe_data[2] = {0x11223344u, 0x55667788u};

static void finish(uint32_t pass, uint32_t code){
    asm volatile(
        "mv x3, %0\n\t"
        "li x26, 1\n\t"
        "mv x27, %1\n\t"
        :
        : "r"(code), "r"(pass)
        : "x3", "x26", "x27"
    );
    while(1){}
}

void serr_handler(uint32_t mcause, uint32_t mepc){
    if(mcause == MCAUSE_LOAD_ADDR_MISALIGNED){
        finish(1u, 0u);
    }
    finish(0u, mcause);
}

int main(void){
    uintptr_t base = (uintptr_t)&probe_data[0];
    uintptr_t misaligned = base + 2u;
    uint32_t value;

    asm volatile("lw %0, 0(%1)" : "=r"(value) : "r"(misaligned));
    (void)value;
    finish(0u, 33u);
    return 0;
}
