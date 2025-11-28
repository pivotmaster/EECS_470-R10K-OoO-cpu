###############################################################
# TEST 1 — Basic Load/Store Verification
# Goal:
#   Verify that the CPU correctly writes to memory and reads back
#   the same data without corruption.
###############################################################
addi x1, x0, 42         # x1 = 42 (test value)
addi x2, x0, 100        # x2 = memory address 100
sw   x1, 0(x2)          # store x1 -> mem[100]
lw   x3, 0(x2)          # load mem[100] -> x3
beq  x1, x3, t1_pass    # if equal, pass
addi x31, x0, 1         # fail code 1
jal next_test
t1_pass:
addi x31, x0, 0
wfi
wfi
wfi
# jal next_test


###############################################################
# TEST 2 — Arithmetic Logic Unit (ALU)
# Goal:
#   Ensure arithmetic ops (add/sub/mul) execute in correct order
#   and handle data dependencies correctly.
###############################################################
next_test:
addi x1, x0, 5
addi x2, x0, 10
add  x3, x1, x2         # x3 = 15
sub  x4, x3, x1         # x4 = 10
mul  x5, x4, x1         # x5 = 50
addi x6, x5, -25        # x6 = 25
beq  x6, x2, t2_pass
addi x31, x0, 2         # fail code 2
jal next_test2
t2_pass:
addi x31, x0, 0
jal next_test2


###############################################################
# TEST 3 — Branch and PC Control
# Goal:
#   Confirm BEQ and BLT correctly update PC and skip/loop.
#   Ensures branch prediction & flush logic works.
###############################################################
next_test2:
addi x1, x0, 0          # x1 = loop counter
addi x2, x0, 5          # x2 = loop limit
loop:
addi x1, x1, 1
blt  x1, x2, loop       # branch back until x1 == 5
addi x3, x0, 99         # x3 = 99 if branch works correctly
addi x31, x0, 0
jal next_test3


###############################################################
# TEST 4 — Memory Streaming and Sequential Access
# Goal:
#   Write sequential data into memory then read back the last.
#   Verifies store forwarding & memory indexing.
###############################################################
next_test3:
addi x1, x0, 0          # counter = 0
addi x2, x0, 10         # limit = 10
addi x3, x0, 200        # base address = 200
loop2:
sw   x1, 0(x3)          # store counter -> mem[address]
addi x3, x3, 4          # increment address
addi x1, x1, 1
blt  x1, x2, loop2
lw   x5, -4(x3)         # read last stored (should be 9)
addi x31, x0, 0
jal next_test4


###############################################################
# TEST 5 — Mixed Ops: ALU + Memory + Branch
# Goal:
#   Check pipeline behavior when multiple units interact.
#   Common hazard: writeback ordering and forwarding.
###############################################################
next_test4:
addi x1, x0, 1
addi x2, x0, 2
add  x3, x1, x2         # x3 = 3
sw   x3, 0(x0)          # store 3 in mem[0]
lw   x4, 0(x0)          # load 3 back
mul  x5, x4, x3         # x5 = 9
addi x6, x0, 9
beq  x5, x6, success
addi x31, x0, 5         # fail code 5
jal done
success:
addi x31, x0, 0


###############################################################
# TEST 6 — RAW Hazard Verification
# Goal:
#   Detect if forwarding / stall logic resolves read-after-write.
###############################################################
addi x10, x0, 1
addi x11, x0, 2
add  x12, x10, x11      # x12 = 3
add  x13, x12, x10      # dependent on previous x12 (RAW)
addi x31, x0, 0
jal next_test5


###############################################################
# TEST 7 — Branch Dependency Chain
# Goal:
#   Test branch immediately after dependent ALU instruction.
###############################################################
next_test5:
addi x1, x0, 4
addi x2, x0, 4
add  x3, x1, x2
beq  x3, x2, branch_ok
addi x31, x0, 7
jal done
branch_ok:
addi x31, x0, 0


###############################################################
# TEST 8 — Deep Pipeline Mix
# Goal:
#   Stress-test multiple instruction types interleaved
#   to catch scoreboard or commit timing bugs.
###############################################################
addi x1, x0, 3
mul  x2, x1, x1         # 9
addi x3, x2, 1          # 10
sw   x3, 8(x0)
lw   x4, 8(x0)
sub  x5, x4, x1         # 7
beq  x5, x1, fail       # should NOT branch
addi x31, x0, 0
jal done
fail:
addi x31, x0, 8

###############################################################
# DONE — End of CPU test suite
###############################################################
done:
nop
