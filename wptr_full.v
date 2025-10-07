module wptr_full (i_clk, i_rst, i_inc, i_rPtr, o_wPtr, o_wAddr, o_full);

  parameter ADDR_W = 4;

  input  i_clk;
  input  i_rst;
  input  i_inc;
  input  [ADDR_W:0] i_rPtr;

  output [ADDR_W:0]   o_wPtr;
  output [ADDR_W-1:0] o_wAddr;
  output o_full;

  reg [ADDR_W:0] counter_d, counter_q;
  reg [ADDR_W:0] grayCounter_d, grayCounter_q;
  reg full_d, full_q;

  reg [ADDR_W:0]   o_wPtr;
  reg [ADDR_W-1:0] o_wAddr;
  reg o_full;

  // Binary counter (next-state logic): 只有未滿時才前進
  always @(*) begin
    counter_d = counter_q + {{ADDR_W{1'b0}}, (i_inc & ~o_full)};
    o_wAddr   = counter_q[ADDR_W-1:0];
  end

  // Binary counter (sequential)
  always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
      counter_q <= { (ADDR_W+1){1'b0} };
    else
      counter_q <= counter_d;
  end

  // Gray counter (next-state logic)
  always @(*) begin
    grayCounter_d = (counter_d >> 1) ^ counter_d;
  end

  // Gray counter (sequential)
  always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
      grayCounter_q <= { (ADDR_W+1){1'b0} };
    else
      grayCounter_q <= grayCounter_d;
  end
  
  // === 這裡開始：改成用「二進位」比較滿條件（等價但更不易出錯） ===

  // Gray -> Binary 小函式（把「同步後」的 rPtr 轉回 binary）
  function [ADDR_W:0] gray2bin;
    input [ADDR_W:0] g;
    integer i;
    begin
      gray2bin[ADDR_W] = g[ADDR_W];
      for (i = ADDR_W-1; i >= 0; i = i-1)
        gray2bin[i] = gray2bin[i+1] ^ g[i];
    end
  endfunction

  wire [ADDR_W:0] rbin_sync = gray2bin(i_rPtr);  // 對向「同步後」指標（binary）
  wire [ADDR_W:0] wbin_next = counter_d;         // 你本來就算好的下一拍 write binary

  // Full detection：二進位條件
  // 低位相等，最高位相反 → 下一筆會「繞過」對方 => 滿
  always @(*) begin
    full_d = ( (wbin_next[ADDR_W-1:0] == rbin_sync[ADDR_W-1:0]) &&
               (wbin_next[ADDR_W]     != rbin_sync[ADDR_W]) );
  end

  // === 到這裡為止；其餘維持不變 ===

//  // Full detection：用 next Gray 與同步過來的 rPtr 比較（MSB 反轉規則）
//  always @(*) begin
//    full_d = (grayCounter_d == {~i_rPtr[ADDR_W:ADDR_W-1], i_rPtr[ADDR_W-2:0]});
//  end

  // Full detection (sequential)
  always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
      full_q <= 1'b0;
    else
      full_q <= full_d;
  end

  // 穩定輸出：跨域指標用已暫存的 Gray；滿旗標用已暫存的值
  always @(*) begin
    o_wPtr = grayCounter_q;
    o_full = full_q;
  end
  
    // ==================================================
  // Debug code 只在模擬用，綜合時會被忽略
  // ==================================================
  // synthesis translate_off
  initial begin
    $display("[%0t] wptr_full USING BINARY full detection (ADDR_W=%0d)", $time, ADDR_W);
  end

  always @(posedge i_clk) begin
    if (i_inc) begin
      $display("[%0t][wptr_full] i_inc=%0b o_full=%0b  wbin_next=%0d  full_d=%0b  full_q=%0b",
               $time, i_inc, o_full, counter_d, full_d, full_q);
    end
  end
  // synthesis translate_on
endmodule
