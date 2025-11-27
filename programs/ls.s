li      x1, 0x100          # x1 = base address 100
li      x2, 0x12345678   # x2 = store data

sw      x2, 0(x1)        # MEM[100] = x2

lw      x3, 0(x1)        # x3 = MEM[100]
wfi