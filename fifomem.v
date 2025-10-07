module fifomem (i_wClk, i_wClkEn, i_wAddr, i_wData, i_wFull, i_rAddr, o_rData);

  parameter DATA_W = 8;
  parameter ADDR_W = 4;

  input  i_wClk;
  input  i_wClkEn;
  input  [ADDR_W-1:0] i_wAddr;
  input  [DATA_W-1:0] i_wData;
  input  i_wFull;

  input  [ADDR_W-1:0] i_rAddr;

  output [DATA_W-1:0] o_rData;
  
  //reg [DATA_W-1:0] o_rData;

  localparam DEPTH = 1 << ADDR_W;
  reg [DATA_W-1:0] mem [0:DEPTH-1];

  // Read
    assign o_rData = mem[i_rAddr];

  // Write
  always @(posedge i_wClk) begin
    if (i_wClkEn)
      mem[i_wAddr] <= i_wData;
  end

endmodule
