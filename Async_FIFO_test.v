`timescale 1ns/1ps

module Async_FIFO_test;

  // ----------------------------------------------------------------
  // Parameters (必須與 DUT 一致；這裡使用各模組的預設值)
  // ----------------------------------------------------------------
  parameter DATA_W = 8;
  parameter ADDR_W = 4;
  localparam DEPTH = 1 << ADDR_W;

  // ----------------------------------------------------------------
  // DUT I/O
  // ----------------------------------------------------------------
  reg                  i_wClk;
  reg                  i_wArst;
  reg                  i_wInc;
  reg  [DATA_W-1:0]    i_wData;
  reg                  i_wFull; // 保留但未使用：DUT 的 fifoTop 介面包含它
  reg                  i_rClk;
  reg                  i_rArst;
  reg                  i_rInc;
  wire [DATA_W-1:0]    o_rData;
  wire                 o_rEmpty;
  wire                 o_wFull;

  // ----------------------------------------------------------------
  // DUT
  // ----------------------------------------------------------------
  Async_FIFO dut (
    .i_wClk  (i_wClk),
    .i_wArst (i_wArst),
    .i_wInc  (i_wInc),
    .i_wData (i_wData),
    .i_wFull (i_wFull), // 未使用，接 0

    .i_rClk  (i_rClk),
    .i_rArst (i_rArst),
    .i_rInc  (i_rInc),

    .o_rData (o_rData),
    .o_rEmpty(o_rEmpty),
    .o_wFull (o_wFull)
  );

  // ----------------------------------------------------------------
  // Clocks (異步雙時鐘，期間會換頻以覆蓋不同比率)
  // ----------------------------------------------------------------
  real wclk_half = 3.0;  // 初始 166.7 MHz
  real rclk_half = 5.0;  // 初始 100.0 MHz

  initial begin
    i_wClk = 0;
    forever #(wclk_half) i_wClk = ~i_wClk;
  end

  initial begin
    i_rClk = 0;
    forever #(rclk_half) i_rClk = ~i_rClk;
  end

  // ----------------------------------------------------------------
  // Reset（非同步，高有效）
  // ----------------------------------------------------------------
  initial begin
    i_wArst = 1'b1;
    i_rArst = 1'b1;
    i_wInc  = 1'b0;
    i_rInc  = 1'b0;
    i_wData = {DATA_W{1'b0}};
    i_wFull = 1'b0; // fifoTop 內部未使用
    repeat (4) @(posedge i_wClk);
    i_wArst = 1'b0;
    repeat (3) @(posedge i_rClk);
    i_rArst = 1'b0;
  end

  // ----------------------------------------------------------------
  // 參考模型（環形佇列）＆ 驗證
  // ----------------------------------------------------------------
  reg [DATA_W-1:0] ref_q [0:DEPTH-1];
  //integer ref_count;
  integer ref_wr_ptr, ref_rd_ptr, ref_count_disp;
  integer total_push, total_pop, err_cnt;
  
  always @(*) ref_count_disp = total_push - total_pop;
  
    // ===== 監控區塊：用跨域事件粗估兩邊視角的佔用度，並檢查旗標合理性 =====

  // 1) 在 rclk 域觀察「成功寫入」穿越同步器（近似 2 拍延遲）
  integer push_seen_in_rclk;
  reg [1:0] w_en_ok_sync_r;
  initial begin
    push_seen_in_rclk = 0;
    w_en_ok_sync_r    = 2'b00;
  end
  always @(posedge i_rClk or posedge i_rArst) begin
    if (i_rArst) begin
      w_en_ok_sync_r    <= 2'b00;
    end else begin
      // 成功寫入事件（在 TB 定義與 DUT 相同：i_wInc && !o_wFull）
      w_en_ok_sync_r    <= {w_en_ok_sync_r[0], (i_wInc && !o_wFull)};
      if (w_en_ok_sync_r == 2'b01)
        push_seen_in_rclk <= push_seen_in_rclk + 1;
    end
  end

  // 2) 在 wclk 域觀察「成功讀出」穿越同步器（近似 2 拍延遲）
  integer pop_seen_in_wclk;
  reg [1:0] r_pop_ok_sync_w;
  initial begin
    pop_seen_in_wclk = 0;
    r_pop_ok_sync_w  = 2'b00;
  end
  always @(posedge i_wClk or posedge i_wArst) begin
    if (i_wArst) begin
      r_pop_ok_sync_w  <= 2'b00;
    end else begin
      r_pop_ok_sync_w  <= {r_pop_ok_sync_w[0], (i_rInc && !o_rEmpty)};
      if (r_pop_ok_sync_w == 2'b01)
        pop_seen_in_wclk <= pop_seen_in_wclk + 1;
    end
  end

  // 3) 估算兩個時脈域各自看到的佔用度
  integer occ_w, occ_r;
  always @(*) begin
    occ_w = total_push - pop_seen_in_wclk;   // wclk 視角占用
    occ_r = push_seen_in_rclk - total_pop;   // rclk 視角占用
  end

  // 4) 旗標合理性檢查（接近邊界但旗標沒亮就警告；允許幾拍延遲）
  always @(posedge i_wClk) begin
    if (occ_w >= (DEPTH-1) && !o_wFull) begin
      $display("[%0t][W] WARNING: occ_w=%0d close to FULL but o_wFull=0", $time, occ_w);
    end
  end
  always @(posedge i_rClk) begin
    if (occ_r <= 0 && !o_rEmpty) begin
      $display("[%0t][R] WARNING: occ_r=%0d close to EMPTY but o_rEmpty=0", $time, occ_r);
    end
  end

  // 5) 第一次資料對比失敗時，印出關鍵狀態（佔用等）
  reg first_mismatch_reported;
  initial first_mismatch_reported = 1'b0;
  always @(posedge i_rClk) begin
    if (!first_mismatch_reported && (i_rInc && !o_rEmpty)) begin
      if (o_rData !== ref_q[ref_rd_ptr]) begin
        first_mismatch_reported <= 1'b1;
        $display("[%0t][MISMATCH] DUT=%0h, EXP=%0h, rd_ptr=%0d, occ_w=%0d, occ_r=%0d",
                 $time, o_rData, ref_q[ref_rd_ptr], ref_rd_ptr, occ_w, occ_r);
      end
    end
  end

  // （加碼）旗標出現時提示一下，方便你在 log 追蹤
  always @(posedge i_wClk) if (o_wFull)  $display("[%0t] FULL asserted",  $time);
  always @(posedge i_rClk) if (o_rEmpty) $display("[%0t] EMPTY asserted", $time);
  
  // === 直接用層級參照檢查寫端下一拍「滿」條件是否曾成立 ===
  // 注意：模組實例名必須跟你的 Async_FIFO.v 一致（u_wptr_full / u_syncR2W）
  wire [ADDR_W:0] wgray_next_chk = dut.u_wptr_full.grayCounter_d;
  wire [ADDR_W:0] rgray_wclk_chk = dut.u_syncR2W.syncPtr_q2;
  wire            full_cond_next = (wgray_next_chk ==
                                   {~rgray_wclk_chk[ADDR_W:ADDR_W-1],
                                     rgray_wclk_chk[ADDR_W-2:0]});
  
  always @(posedge i_wClk) begin
    if (full_cond_next)
      $display("[%0t][CHK] NEXT FULL condition matched in wptr_full", $time);
  end
  
  // ===== 監控區塊結束：用跨域事件粗估兩邊視角的佔用度，並檢查旗標合理性 =====

  initial begin
    ref_wr_ptr = 0;
    ref_rd_ptr = 0;
    //ref_count  = 0;
    total_push = 0;
    total_pop  = 0;
    err_cnt    = 0;
  end

  // 寫入面：在 wClk 邊緣記錄「實際被接受的寫入」
  always @(posedge i_wClk or posedge i_wArst) begin
    if (i_wArst) begin
      ref_wr_ptr <= 0;
      //ref_count  <= 0;
      total_push <= 0;
    end else begin
      // 真正寫入成立條件：i_wInc 且 !o_wFull（與 fifomem gate 一致）
      if (i_wInc && !o_wFull) begin
        ref_q[ref_wr_ptr] <= i_wData;
        ref_wr_ptr <= (ref_wr_ptr + 1) % DEPTH;
        //ref_count  <= ref_count + 1;
        total_push <= total_push + 1;
        // 參考模型不應溢位
        if (ref_count_disp + 1 > DEPTH) begin
          $display("[%0t] ERROR: Reference queue overflow!", $time);
          err_cnt <= err_cnt + 1;
        end
      end
    end
  end

  // 讀出面：在 rClk 邊緣比對「實際被接受的讀出」
  // 真正讀出成立條件：i_rInc 且 !o_rEmpty
  reg [DATA_W-1:0] last_rData; // 用於觀察，但比較用 o_rData
  always @(posedge i_rClk or posedge i_rArst) begin
    if (i_rArst) begin
      ref_rd_ptr <= 0;
      total_pop  <= 0;
      last_rData <= {DATA_W{1'b0}};
    end else begin
      if (i_rInc && !o_rEmpty) begin
        last_rData <= o_rData;
        if (ref_count_disp <= 0) begin
          $display("[%0t] ERROR: Read when reference queue empty!", $time);
          err_cnt <= err_cnt + 1;
        end else begin
          if (o_rData !== ref_q[ref_rd_ptr]) begin
            $display("[%0t] ERROR: Data mismatch. DUT=%0h, REF=%0h (rd_ptr=%0d)",
                     $time, o_rData, ref_q[ref_rd_ptr], ref_rd_ptr);
            err_cnt <= err_cnt + 1;
          end
          ref_rd_ptr <= (ref_rd_ptr + 1) % DEPTH;
          //ref_count  <= ref_count - 1;
          total_pop  <= total_pop + 1;
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // 產生刺激：隨機寫入/讀出請求（遵守 full/empty）
  // 同時安排幾個階段切換時鐘比率，覆蓋 corner cases
  // ----------------------------------------------------------------
  // 控制是否啟用隨機寫/讀激勵
  reg stim_en_w = 1'b1;
  reg stim_en_r = 1'b1;
  
  integer guard;
  integer seed;
  initial seed = 32'h1BADB002;

  // 寫入產生器（write domain）
  always @(posedge i_wClk or posedge i_wArst) begin
    if (i_wArst) begin
      i_wInc  <= 1'b0;
      i_wData <= {DATA_W{1'b0}};
	 end else if (!stim_en_w) begin
		i_wInc <= 1'b0;
    end else begin
      // 70% 機率在未滿時提出寫請求
      if (!o_wFull && ($random(seed) % 10 < 7)) begin
        i_wInc  <= 1'b1;
        i_wData <= $random(seed);
      end else begin
        i_wInc  <= 1'b0;
      end
    end
  end

  // 讀出產生器（read domain）
  always @(posedge i_rClk or posedge i_rArst) begin
    if (i_rArst) begin
      i_rInc <= 1'b0;
	 end else if (!stim_en_r) begin
		i_rInc <= 1'b0;
    end else begin
      // 65% 機率在非空時提出讀請求
      if (!o_rEmpty && ($random(seed) % 20 < 13)) begin
        i_rInc <= 1'b1;
      end else begin
        i_rInc <= 1'b0;
      end
    end
  end

  // ----------------------------------------------------------------
  // 測試情境排程：換頻、脈衝 reset、持續跑壓力測試
  // ----------------------------------------------------------------
  initial begin
    // 波形
    $dumpfile("Async_FIFO_test.vcd");
    $dumpvars(0, Async_FIFO_test);

    // 等待 reset 完成
    @(negedge i_wArst);
    @(negedge i_rArst);
	 
	 //Debug
	 stim_en_w = 1'b0;  // 關掉隨機寫
    stim_en_r = 1'b0;  // 關掉隨機讀
	 
    // 停讀，專心寫到滿
    repeat (2) @(posedge i_rClk); i_rInc <= 1'b0;

    // 連續寫直到滿
	 guard = 0;
    while (!o_wFull && guard < 100000) begin
      @(posedge i_wClk);
      i_wInc  <= 1'b1;
      i_wData <= $random(seed);
		guard = guard + 1;
    end
    @(posedge i_wClk) i_wInc <= 1'b0;
	 
	 if(guard >= 100000) begin
		$display("[%0t] TIMEOUT waiting o_wFull=1 in forced fill", $time);
		$stop;
	 end
    $display("[%0t] TB: observed o_wFull=1 after forced fill", $time);

    // 開始排空
    @(posedge i_rClk);
    i_rInc <= 1'b1;
	 guard = 0;
    while (!o_rEmpty && guard < 100000) begin
		@(posedge i_rClk);
		guard = guard + 1;
	 end
    i_rInc <= 1'b0;
	 
	 if(guard >= 100000)begin
		$display("[%0t] TIMEOUT waiting o_rEmpty=1 in forced drain", $time);
		$stop;
	 end
    $display("[%0t] TB: observed o_rEmpty=1 after forced drain", $time);
	 
	 // 恢復隨機激勵
	 stim_en_w = 1'b1;
	 stim_en_r = 1'b1;
	 // ===== Debug 區塊結束 =====

    // Phase 1：寫比讀快
    $display("[%0t] Phase 1: write faster than read", $time);
    #(20000);

    // Phase 2：讀比寫快
    $display("[%0t] Phase 2: read faster than write", $time);
    wclk_half = 6.0;  // ~83 MHz
    rclk_half = 2.5;  // 200 MHz
    #(20000);

    // Phase 3：相近頻率＋短暫 reset 抖動（讀域）
    $display("[%0t] Phase 3: near-rate + read side reset pulse", $time);
    wclk_half = 3.5;  // ~142.9 MHz
    rclk_half = 3.0;  // ~166.7 MHz

    // 插入一次 read-side async reset 脈衝，檢查恢復行為
    #(1500);
    i_rArst = 1'b1;
    #(25);
    i_rArst = 1'b0;

    #(20000);

    // Phase 4：滿載填充至 full，再釋放
    $display("[%0t] Phase 4: force fill to FULL then drain", $time);
    force_fill_then_drain();

    // 收尾
    #(5000);
    summary_and_finish();
  end

  // ----------------------------------------------------------------
  // 任務：填滿到 full，再讀空
  // ----------------------------------------------------------------
  task force_fill_then_drain;
    integer n;
    begin
      // 停止讀出，專心填滿
      @(posedge i_rClk); i_rInc <= 1'b0;

      // 連續寫直到 full
      while (!o_wFull) begin
        @(posedge i_wClk);
        i_wInc  <= 1'b1;
        i_wData <= $random(seed);
      end
      @(posedge i_wClk) i_wInc <= 1'b0;

      // 確認 full 標誌
      if (!o_wFull) begin
        $display("[%0t] WARNING: expected FULL but flag not high", $time);
      end

      // 開始排空
      @(posedge i_rClk);
      i_rInc <= 1'b1;
      while (!o_rEmpty) @(posedge i_rClk);
      i_rInc <= 1'b0;

      // 確認 empty 標誌
      if (!o_rEmpty) begin
        $display("[%0t] WARNING: expected EMPTY but flag not high", $time);
      end
    end
  endtask

  // ----------------------------------------------------------------
  // 總結
  // ----------------------------------------------------------------
  task summary_and_finish;
    begin
      $display("------------------------------------------------------------");
      $display("Simulation Summary @ %0t", $time);
      $display("  DATA_W      = %0d", DATA_W);
      $display("  ADDR_W      = %0d (DEPTH=%0d)", ADDR_W, DEPTH);
      $display("  total_push  = %0d", total_push);
      $display("  total_pop   = %0d", total_pop);
      //$display("  ref_count   = %0d", ref_count);
		$display("  ref_count   = %0d", ref_count_disp);
      $display("  errors      = %0d", err_cnt);
      $display("  o_wFull     = %0b", o_wFull);
      $display("  o_rEmpty    = %0b", o_rEmpty);
      $display("------------------------------------------------------------");
      if (err_cnt == 0) begin
        $display("TEST PASS");
      end else begin
        $display("TEST FAIL  (errors=%0d)", err_cnt);
      end
      //$finish;
		$stop;
    end
  endtask

endmodule
