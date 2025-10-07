module Async_FIFO (i_wClk, i_wArst, i_wInc, i_wData, i_wFull, i_rClk, i_rArst, i_rInc, o_rData, o_rEmpty, o_wFull);

  parameter DATA_W = 8;
  parameter ADDR_W = 4;

  input  i_wClk;
  input  i_wArst;
  input  i_wInc;
  input  [DATA_W-1:0] i_wData;
  input  i_wFull;   // 保留與原介面一致（未使用）

  input  i_rClk;
  input  i_rArst;
  input  i_rInc;

  output [DATA_W-1:0] o_rData;
  output              o_rEmpty;
  output              o_wFull;

  // 內部連線
  wire [ADDR_W:0]   wPtr, syncWptr;
  wire [ADDR_W:0]   rPtr, syncRptr;
  wire [ADDR_W-1:0] wAddr, rAddr;

  // --------------------
  // Write 
  // --------------------
  sync u_syncR2W (
      .i_clk     (i_wClk),
      .i_arst    (i_wArst),
      .i_ptr     (rPtr),
      .o_syncPtr (syncRptr)
  );

  wptr_full u_wptr_full (
      .i_clk   (i_wClk),
      .i_rst   (i_wArst),
      .i_inc   (i_wInc),
      .i_rPtr  (syncRptr),
      .o_wPtr  (wPtr),
      .o_wAddr (wAddr),
      .o_full  (o_wFull)
  );

  // --------------------
  // Memory
  // --------------------
  
  wire w_en_ok = i_wInc && !o_wFull;
  
  fifomem u_fifomem (
      .i_wClk   (i_wClk),
      .i_wClkEn (w_en_ok),
      .i_wAddr  (wAddr),
      .i_wData  (i_wData),
      .i_wFull  (o_wFull),  // 寫滿時禁止寫入
      .i_rAddr  (rAddr),
      .o_rData  (o_rData)
  );

  // --------------------
  // Read 
  // --------------------
  sync u_syncW2R (
      .i_clk     (i_rClk),
      .i_arst    (i_rArst),
      .i_ptr     (wPtr),
      .o_syncPtr (syncWptr)
  );

  rptr_empty u_rptr_empty (
      .i_clk   (i_rClk),
      .i_arst  (i_rArst),
      .i_inc   (i_rInc),
      .i_wPtr  (syncWptr),
      .o_rPtr  (rPtr),
      .o_rAddr (rAddr),
      .o_empty (o_rEmpty)
  );

endmodule
