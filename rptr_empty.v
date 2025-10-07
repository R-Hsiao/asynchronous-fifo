module rptr_empty (i_clk, i_arst, i_inc, i_wPtr, o_rPtr, o_rAddr, o_empty);

  parameter ADDR_W = 4;

  input  i_clk;
  input  i_arst;
  input  i_inc;
  input  [ADDR_W:0] i_wPtr;

  output [ADDR_W:0]   o_rPtr;
  output [ADDR_W-1:0] o_rAddr;
  output              o_empty;

  reg [ADDR_W:0] counter_d, counter_q;
  reg [ADDR_W:0] grayCounter_d, grayCounter_q;
  reg            empty_d, empty_q;

  reg [ADDR_W:0]   o_rPtr;
  reg [ADDR_W-1:0] o_rAddr;
  reg              o_empty;

  // Binary counter (next-state logic): 只有非空時才前進
  always @(*) begin
    counter_d = counter_q + {{ADDR_W{1'b0}}, (i_inc & ~o_empty)};
    o_rAddr   = counter_q[ADDR_W-1:0];
  end

  // Binary counter (sequential)
  always @(posedge i_clk or posedge i_arst) begin
    if (i_arst)
      counter_q <= { (ADDR_W+1){1'b0} };
    else
      counter_q <= counter_d;
  end

  // Gray counter (next-state logic)
  always @(*) begin
    grayCounter_d = (counter_d >> 1) ^ counter_d;
  end

  // Gray counter (sequential)
  always @(posedge i_clk or posedge i_arst) begin
    if (i_arst)
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

  wire [ADDR_W:0] wbin_sync = gray2bin(i_wPtr);  // 已同步到 rclk 的寫指標（binary）
  wire [ADDR_W:0] rbin_next = counter_d;         // 下一拍的讀指標（binary）

//  // Empty detection：用 next Gray 與同步過來的 wPtr 比較
//  always @(*) begin
//    empty_d = (rbin_next == wbin_sync);
//  end

  // Empty detection (sequential)
  always @(posedge i_clk or posedge i_arst) begin
    if (i_arst)
      empty_q <= 1'b1;
    else
      empty_q <= empty_d;
  end

  // 穩定輸出：跨域指標用已暫存的 Gray；空旗標用已暫存的值
  always @(*) begin
    o_rPtr  = grayCounter_q;
    o_empty = empty_q;
  end
  
endmodule
