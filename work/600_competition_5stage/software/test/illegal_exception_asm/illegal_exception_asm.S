.section .text
.global entry
entry:
    li sp, 0x10008000
    la t0, trap_entry
    csrw mtvec, t0
    .word 0xffffffff
    li gp, 32
    li s10, 1
    li s11, 0
1:
    j 1b

trap_entry:
    csrr t0, mcause
    li t1, 2
    bne t0, t1, fail
    li gp, 0
    li s10, 1
    li s11, 1
2:
    j 2b

fail:
    mv gp, t0
    li s10, 1
    li s11, 0
3:
    j 3b
