// AXI4-Stream FIFO: bytes and their TLAST go in on the slave side and come
// out on the master side in the same order. Each FIFO slot stores TLAST
// together with the data byte.
//   Input side:  S_TREADY = not full;  a byte is stored when S_TVALID and S_TREADY.
//   Output side: M_TVALID = not empty; the front byte leaves when M_TVALID and M_TREADY.
// Synchronous active-low reset (ARESETn) empties the FIFO.

`timescale 1ns/1ps

module axis_fifo #(
  parameter int DATA_W = 8,    // bits per byte of TDATA
  parameter int DEPTH  = 16    // number of slots
)(
  input  logic              i_ACLK,
  input  logic              i_ARESETn,

  // Slave side: bytes come in
  input  logic              i_S_TVALID,
  output logic              o_S_TREADY,
  input  logic [DATA_W-1:0] i_S_TDATA,
  input  logic              i_S_TLAST,

  // Master side: bytes go out
  output logic              o_M_TVALID,
  input  logic              i_M_TREADY,
  output logic [DATA_W-1:0] o_M_TDATA,
  output logic              o_M_TLAST
);

  logic            w_Full;
  logic            w_Empty;
  logic [DATA_W:0] w_Rd_Slot;        // TLAST in the top bit, data below

  fifo_count #(
    .WIDTH(DATA_W + 1),
    .DEPTH(DEPTH)
  ) u_fifo (
    .i_Clk    (i_ACLK),
    .i_Rst_n  (i_ARESETn),
    .i_Wr_En  (i_S_TVALID & o_S_TREADY),
    .i_Wr_Data({i_S_TLAST, i_S_TDATA}),
    .i_Rd_En  (o_M_TVALID & i_M_TREADY),
    .o_Rd_Data(w_Rd_Slot),
    .o_Empty  (w_Empty),
    .o_Full   (w_Full)
  );

  assign o_S_TREADY = ~w_Full;
  assign o_M_TVALID = ~w_Empty;
  assign o_M_TDATA  = w_Rd_Slot[DATA_W-1:0];
  assign o_M_TLAST  = w_Rd_Slot[DATA_W];

endmodule