li      x1, 0x60          # x1 = base address 100
li      x2, 0x12345678   # x2 = store data
sw      x2, 0(x1)        # MEM[100] = x2
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
addi    x1, x1, 0x1
addi    x2, x2, 0x1
sw      x2, 0(x1)
lw      x3, 0(x1)        # x3 = MEM[100]
wfi