`timescale 1ns/1ps

module tb_rob_only;

  logic start_sim;

  // Parameters match ROB
  localparam int DEPTH          = 64;
  localparam int INST_W         = 16;
  localparam int DISPATCH_WIDTH = 2;
  localparam int COMMIT_WIDTH   = 2;
  localparam int WB_WIDTH       = 4;
  localparam int ARCH_REGS      = 64;
  localparam int PHYS_REGS      = 128;
  localparam int XLEN           = 64;

  // Clock/reset
  logic clk, reset;

  // DUT I/O
  logic [DISPATCH_WIDTH-1:0] disp_valid_i, disp_rd_wen_i;
  logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] disp_rd_arch_i;
  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_i;
  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_i;
  logic [DISPATCH_WIDTH-1:0] disp_ready_o, disp_alloc_o;
  logic [DISPATCH_WIDTH-1:0][$clog2(DEPTH)-1:0] disp_rob_idx_o;

  logic [WB_WIDTH-1:0] wb_valid_i, wb_exception_i, wb_mispred_i;
  logic [WB_WIDTH-1:0][$clog2(DEPTH)-1:0] wb_rob_idx_i;

  logic [COMMIT_WIDTH-1:0] commit_valid_o, commit_rd_wen_o;
  logic [COMMIT_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] commit_rd_arch_o;
  logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] commit_new_prf_o;
  logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] commit_old_prf_o;

  logic flush_o;
  logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o;

  // Instantiate ROB
  rob #(
    .DEPTH(DEPTH), .INST_W(INST_W),
    .DISPATCH_WIDTH(DISPATCH_WIDTH), .COMMIT_WIDTH(COMMIT_WIDTH),
    .WB_WIDTH(WB_WIDTH), .ARCH_REGS(ARCH_REGS),
    .PHYS_REGS(PHYS_REGS), .XLEN(XLEN)
  ) dut (
    .clk(clk), .reset(reset),
    .disp_valid_i(disp_valid_i), .disp_rd_wen_i(disp_rd_wen_i),
    .disp_rd_arch_i(disp_rd_arch_i),
    .disp_rd_new_prf_i(disp_rd_new_prf_i),
    .disp_rd_old_prf_i(disp_rd_old_prf_i),
    .disp_ready_o(disp_ready_o), .disp_alloc_o(disp_alloc_o),
    .disp_rob_idx_o(disp_rob_idx_o),
    .wb_valid_i(wb_valid_i), .wb_rob_idx_i(wb_rob_idx_i),
    .wb_exception_i(wb_exception_i), .wb_mispred_i(wb_mispred_i),
    .commit_valid_o(commit_valid_o), .commit_rd_wen_o(commit_rd_wen_o),
    .commit_rd_arch_o(commit_rd_arch_o),
    .commit_new_prf_o(commit_new_prf_o),
    .commit_old_prf_o(commit_old_prf_o),
    .flush_o(flush_o), .flush_upto_rob_idx_o(flush_upto_rob_idx_o)
  );

  // Clock
  always #5 clk = ~clk;

  // Reset
  initial begin
    clk = 0; reset = 1;
    repeat (3) @(negedge clk);
    reset = 0;
  end
  
  // Stimulus: multiple dispatch/writeback/flush tests
  int total_dispatched, prf_counter, ridx;
  initial begin
    // === init ===
    start_sim = 0;
    disp_valid_i = '0; disp_rd_wen_i = '0;
    wb_valid_i   = '0; wb_exception_i = '0; wb_mispred_i = '0;

    @(negedge reset);
    @(negedge clk); // wait reset end

    
     // =====================================================
    // [Phase 1] Dispatch a ins -> commit
    // =====================================================
    $display("\n=== Phase 1: Single Dispatch/Commit ===");
    start_sim = 1;
    @(negedge clk);
    disp_valid_i[0]      = 1;
    disp_rd_wen_i[0]     = 1;
    disp_rd_arch_i[0]    = 5'd1;
    disp_rd_new_prf_i[0] = 7'd10;
    disp_rd_old_prf_i[0] = 7'd2;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback (ROB idx 0)
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 0;

    @(negedge clk);
    wb_valid_i = '0;

    repeat (5) @(negedge clk);

    // =====================================================
    // [Phase 2] dispatch two ways, writeback one way
    // =====================================================
    $display("\n=== Phase 2: Dual Dispatch, Staggered WB ===");
    @(negedge clk);
    disp_valid_i      = 2'b11;
    disp_rd_wen_i     = 2'b11;
    disp_rd_arch_i[0] = 5'd3;  disp_rd_new_prf_i[0] = 7'd11;  disp_rd_old_prf_i[0] = 7'd5;
    disp_rd_arch_i[1] = 5'd4;  disp_rd_new_prf_i[1] = 7'd12;  disp_rd_old_prf_i[1] = 7'd6;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback second（ROB idx 1）
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 2;

    @(negedge clk);
    wb_valid_i = '0;

    // writeback first（ROB idx 2）
    repeat (3) @(negedge clk);
    wb_valid_i[1]   = 1;
    wb_rob_idx_i[1] = 1;

    @(negedge clk);
    wb_valid_i = '0;

    repeat (6) @(negedge clk);

    // =====================================================
    // [Phase 3] test mispredict -> flush
    // =====================================================
    $display("\n=== Phase 3: Mispredict Flush Test ===");
    @(negedge clk);
    disp_valid_i[0]      = 1;
    disp_rd_wen_i[0]     = 1;
    disp_rd_arch_i[0]    = 5'd7;
    disp_rd_new_prf_i[0] = 7'd13;
    disp_rd_old_prf_i[0] = 7'd8;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback, mispred (ROB idx 3)
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 3;
    wb_mispred_i[0] = 1;  // flush

    @(negedge clk);
    wb_valid_i = '0; wb_mispred_i = '0;

    repeat (5) @(negedge clk);

    // =====================================================
    // [Phase 4] dispatch after flush
    // =====================================================
    $display("\n=== Phase 4: Post-Flush Dispatch ===");
    @(negedge clk);
    disp_valid_i[0]      = 1;
    disp_rd_wen_i[0]     = 1;
    disp_rd_arch_i[0]    = 5'd9;
    disp_rd_new_prf_i[0] = 7'd14;
    disp_rd_old_prf_i[0] = 7'd4;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback + Commit (ROB idx 4)
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 4;

    @(negedge clk);
    wb_valid_i = '0;

    repeat (5) @(negedge clk);

    // =====================================================
    // [Phase 5] Commit two ins at the same time
    // =====================================================
    $display("\n=== Phase 5: test Commit two ins at the same time ===");

    @(negedge clk);
    // Dispatch
    disp_valid_i      = 2'b11;
    disp_rd_wen_i     = 2'b11;
    disp_rd_arch_i[0] = 5'd10; disp_rd_new_prf_i[0] = 7'd15; disp_rd_old_prf_i[0] = 7'd3;
    disp_rd_arch_i[1] = 5'd11; disp_rd_new_prf_i[1] = 7'd16; disp_rd_old_prf_i[1] = 7'd4;
    @(negedge clk);
    disp_valid_i = '0;

    // writeback two ins
    @(negedge clk);
    wb_valid_i = 4'b0011;
    wb_rob_idx_i[0] = 5;
    wb_rob_idx_i[1] = 6;
    @(negedge clk);
    
    wb_valid_i = '0;
    @(negedge clk);
    // =====================================================
    // [Phase 6] Dispatch until ROB is full
    // =====================================================
    $display("\n=== Phase 6: Dispatch until ROB is full ===");
    total_dispatched = 0;
    prf_counter = 20;
    while(total_dispatched < 100) begin
      @(negedge clk);
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        disp_valid_i[i]      = 1;
        disp_rd_wen_i[i]     = 1;
        disp_rd_arch_i[i]    = (total_dispatched + 12) % ARCH_REGS;
        disp_rd_new_prf_i[i] = prf_counter + 10;
        disp_rd_old_prf_i[i] = prf_counter;
        total_dispatched++;
        prf_counter++;
        // $display("dispatch 2");
      end
    end
    disp_valid_i = 0;
    @(negedge clk);

    // =====================================================
    // [Phase 7] WB from back
    // =====================================================
    $display("\n=== Phase 7: WB from back ===");
    for (ridx = DEPTH-1; ridx >= 0; ridx--) begin
      @(negedge clk);
      wb_valid_i      = 4'b0011;
      wb_rob_idx_i[0] = ridx;
      if(ridx == DEPTH - 11) begin
        wb_mispred_i[0] = 1;
        $display("%0d is mispred", ridx);
      end else begin
        wb_mispred_i[0] = 0;
      end
      wb_rob_idx_i[1] = (ridx > 0) ? ridx-1 : ridx;
      $display("[%0t] WB two entries: ROB[%0d] and ROB[%0d]", 
               $time, wb_rob_idx_i[0], wb_rob_idx_i[1]);
      ridx--;
    end

    @(negedge clk);
    wb_valid_i = '0;
    $display("\n=== Phase 7 Complete: Reverse writeback finished ===");

    // =====================================================
    // [Phase 8] Alternating mispredict/exception flush
    // =====================================================
    $display("\n=== Phase 8: Alternating mispredict/exception flush ===");
    for (int i = 0; i < 12; i++) begin
      @(negedge clk);
      disp_valid_i = 2'b11;
      for (int k = 0; k < DISPATCH_WIDTH; k++) begin
        disp_rd_arch_i[k] = (i+k) % ARCH_REGS;
        disp_rd_new_prf_i[k] = (50 + i + k) % PHYS_REGS;
        disp_rd_old_prf_i[k] = (70 + i + k) % PHYS_REGS;
      end

      if (i % 3 == 1) begin
        wb_valid_i[0]   = 1;
        wb_rob_idx_i[0] = i % DEPTH;
        wb_mispred_i[0] = 1;
      end else if (i % 3 == 2) begin
        wb_valid_i[1]   = 1;
        wb_rob_idx_i[1] = (i-1) % DEPTH;
        wb_exception_i[1] = 1;
      end else begin
        wb_valid_i = '0; wb_mispred_i = '0; wb_exception_i = '0;
      end
    end
    wb_valid_i = '0; wb_mispred_i = '0; wb_exception_i = '0;
        repeat (40) @(negedge clk);

        repeat (8) @(negedge clk);

        $display("\n=== 8 Simulation Finished ===");
        $finish;

      end

    always @(negedge clk) begin
      if(start_sim) begin
        for(int i = 0; i < COMMIT_WIDTH; i++) begin
          if (commit_valid_o[i])
            $display("[%0t] Commit %0d: arch=%0d new=%0d old=%0d",
                    $time, i, commit_rd_arch_o[i],
                    commit_new_prf_o[i], commit_old_prf_o[i]);
        end
        if (|commit_valid_o)
          $display("commit num: %0d", $countones(commit_valid_o));
        if (flush_o)
          $display("[%0t] Flush up to ROB idx %0d", $time, flush_upto_rob_idx_o);
      end
    end

    // =====================================================
    // Ground Truth
    // =====================================================
    typedef struct packed {
      int arch;
      int new_prf;
      int old_prf;
    } commit_t;

    typedef struct {
      int cycle;
      commit_t commits[$]; 
    } commit_group_t;

    commit_group_t exp_groups[$] = '{
    '{cycle: 9000, commits: '{
        '{arch:1, new_prf:10, old_prf:2}
    }},
    '{cycle: 22000, commits: '{
        '{arch:3, new_prf:11, old_prf:5},
        '{arch:4, new_prf:12, old_prf:6}
    }},
    '{cycle: 32000, commits: '{
        '{arch:7, new_prf:13, old_prf:8}
    }},
    '{cycle: 41000, commits: '{
        '{arch:9, new_prf:14, old_prf:4}
    }},
    '{cycle: 50000, commits: '{
        '{arch:10, new_prf:15, old_prf:3},
        '{arch:11, new_prf:16, old_prf:4}
    }},
    '{cycle: 132000, commits: '{
        '{arch:12, new_prf:30, old_prf:20},
        '{arch:13, new_prf:31, old_prf:21}
    }},
    '{cycle: 133000, commits: '{
        '{arch:14, new_prf:32, old_prf:22},
        '{arch:15, new_prf:33, old_prf:23}
    }},
    '{cycle: 134000, commits: '{
        '{arch:16, new_prf:34, old_prf:24},
        '{arch:17, new_prf:35, old_prf:25}
    }},
    '{cycle: 135000, commits: '{
        '{arch:18, new_prf:36, old_prf:26},
        '{arch:19, new_prf:37, old_prf:27}
    }},
    '{cycle: 136000, commits: '{
        '{arch:20, new_prf:38, old_prf:28},
        '{arch:21, new_prf:39, old_prf:29}
    }},
    '{cycle: 137000, commits: '{
        '{arch:22, new_prf:40, old_prf:30},
        '{arch:23, new_prf:41, old_prf:31}
    }},
    '{cycle: 138000, commits: '{
        '{arch:24, new_prf:42, old_prf:32},
        '{arch:25, new_prf:43, old_prf:33}
    }},
    '{cycle: 139000, commits: '{
        '{arch:26, new_prf:44, old_prf:34},
        '{arch:27, new_prf:45, old_prf:35}
    }},
    '{cycle: 140000, commits: '{
        '{arch:28, new_prf:46, old_prf:36},
        '{arch:29, new_prf:47, old_prf:37}
    }},
    '{cycle: 141000, commits: '{
        '{arch:30, new_prf:48, old_prf:38},
        '{arch:31, new_prf:49, old_prf:39}
    }},
    '{cycle: 142000, commits: '{
        '{arch:32, new_prf:50, old_prf:40},
        '{arch:33, new_prf:51, old_prf:41}
    }},
    '{cycle: 143000, commits: '{
        '{arch:34, new_prf:52, old_prf:42},
        '{arch:35, new_prf:53, old_prf:43}
    }},
    '{cycle: 144000, commits: '{
        '{arch:36, new_prf:54, old_prf:44},
        '{arch:37, new_prf:55, old_prf:45}
    }},
    '{cycle: 145000, commits: '{
        '{arch:38, new_prf:56, old_prf:46},
        '{arch:39, new_prf:57, old_prf:47}
    }},
    '{cycle: 146000, commits: '{
        '{arch:40, new_prf:58, old_prf:48},
        '{arch:41, new_prf:59, old_prf:49}
    }},
    '{cycle: 147000, commits: '{
        '{arch:42, new_prf:60, old_prf:50},
        '{arch:43, new_prf:61, old_prf:51}
    }},
    '{cycle: 148000, commits: '{
        '{arch:44, new_prf:62, old_prf:52},
        '{arch:45, new_prf:63, old_prf:53}
    }},
    '{cycle: 149000, commits: '{
        '{arch:46, new_prf:64, old_prf:54},
        '{arch:47, new_prf:65, old_prf:55}
    }},
    '{cycle: 150000, commits: '{
        '{arch:48, new_prf:66, old_prf:56},
        '{arch:49, new_prf:67, old_prf:57}
    }},
    '{cycle: 151000, commits: '{
        '{arch:50, new_prf:68, old_prf:58},
        '{arch:51, new_prf:69, old_prf:59}
    }},
    '{cycle: 152000, commits: '{
        '{arch:52, new_prf:70, old_prf:60},
        '{arch:53, new_prf:71, old_prf:61}
    }},
    '{cycle: 153000, commits: '{
        '{arch:54, new_prf:72, old_prf:62},
        '{arch:55, new_prf:73, old_prf:63}
    }},
    '{cycle: 154000, commits: '{
        '{arch:56, new_prf:74, old_prf:64},
        '{arch:57, new_prf:75, old_prf:65}
    }},
    '{cycle: 155000, commits: '{
        '{arch:58, new_prf:76, old_prf:66},
        '{arch:59, new_prf:77, old_prf:67}
    }}
  };

  // =====================================================
  // Task for comparing Ground Truth and DUT result
  // =====================================================
  task automatic compare_group(commit_group_t expg, int dut_cnt,
                             int dut_arch[COMMIT_WIDTH],
                             int dut_new [COMMIT_WIDTH],
                             int dut_old [COMMIT_WIDTH]);
  for (int j = 0; j < expg.commits.size(); j++) begin
    commit_t exp = expg.commits[j];
    if (j < dut_cnt &&
        dut_arch[j] == exp.arch &&
        dut_new [j] == exp.new_prf &&
        dut_old [j] == exp.old_prf)
      $display("✅ Match @%0t: arch=%0d new=%0d old=%0d",
               $time, exp.arch, exp.new_prf, exp.old_prf);
    else
      $error("%s", $sformatf("❌ Mismatch @%0t: DUT[%0d] != EXP[%0d]",
                             $time, j, j));
  end
endtask

// =====================================================
// Comparing Ground Truth and DUT result
// =====================================================
int group_idx  = 0;
always @(negedge clk) begin
  if (start_sim && !reset && group_idx < exp_groups.size()) begin
    automatic commit_group_t expg = exp_groups[group_idx];

    if (($time) == (expg.cycle/100)) begin
      automatic int dut_cnt = 0;
      automatic int dut_arch[COMMIT_WIDTH];
      automatic int dut_new [COMMIT_WIDTH];
      automatic int dut_old [COMMIT_WIDTH];
      // Get individual commits data from groups
      for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (dut.commit_valid_o[i]) begin
          dut_arch[dut_cnt] = dut.commit_rd_arch_o[i];
          dut_new [dut_cnt] = dut.commit_new_prf_o[i];
          dut_old [dut_cnt] = dut.commit_old_prf_o[i];
          dut_cnt++;
        end
      end
      // Use Task to compare
      compare_group(expg, dut_cnt, dut_arch, dut_new, dut_old); 
      group_idx++;
    end
  end
end


endmodule
