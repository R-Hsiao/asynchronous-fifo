module sync (i_clk, i_arst, i_ptr, o_syncPtr);

  parameter ADDR_W = 4;

  input  i_clk;
  input  i_arst;
  input  [ADDR_W:0] i_ptr;
  output [ADDR_W:0] o_syncPtr;

  reg [ADDR_W:0] syncPtr_q1;
  reg [ADDR_W:0] syncPtr_q2;
  reg [ADDR_W:0] o_syncPtr;

  // 第一級同步器
  always @(posedge i_clk or posedge i_arst)
    if (i_arst)
      syncPtr_q1 <= { (ADDR_W+1){1'b0} };
    else
      syncPtr_q1 <= i_ptr;

  // 第二級同步器
  always @(posedge i_clk or posedge i_arst)
    if (i_arst)
      syncPtr_q2 <= { (ADDR_W+1){1'b0} };
    else
      syncPtr_q2 <= syncPtr_q1;

  // 輸出
  always @(*) begin
    o_syncPtr = syncPtr_q2;
  end

endmodule
