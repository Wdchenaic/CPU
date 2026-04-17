#include <stdint.h>
#include "../../include/utils.h"

#define MCAUSE_ILLEGAL_INSTRUCTION 2u

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
    if(mcause == MCAUSE_ILLEGAL_INSTRUCTION){
        finish(1u, 0u);
    }
    finish(0u, mcause);
}

int main(void){
    asm volatile(".word 0xffffffff");
    finish(0u, 32u);
    return 0;
}
