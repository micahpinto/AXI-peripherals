// AXI4-Lite slave with a 4-entry register file.
//
// Register map:
//   0x00  CTRL   RW   reset 0
//   0x04  DATA0  RW   reset 0
//   0x08  DATA1  RW   reset 0
//   0x0C  ID     RO   0xA9B0_0001
// Writes to ID, out-of-range and unaligned accesses return SLVERR and change nothing.
// Reads out of range or unaligned return SLVERR with data 0.
// The write address and write data can arrive in either order.
// WSTRB selects which bytes of a register are written.
// One write and one read are handled at a time. Synchronous active-low reset.

`timescale 1ns/1ps

module axi_lite_regs (
  input  logic        i_ACLK,
  input  logic        i_ARESETn,

  // Write address
  input  logic [7:0]  i_AWADDR,
  input  logic [2:0]  i_AWPROT,     // not used
  input  logic        i_AWVALID,
  output logic        o_AWREADY,

  // Write data
  input  logic [31:0] i_WDATA,
  input  logic [3:0]  i_WSTRB,
  input  logic        i_WVALID,
  output logic        o_WREADY,

  // Write response
  output logic [1:0]  o_BRESP,
  output logic        o_BVALID,
  input  logic        i_BREADY,

  // Read address
  input  logic [7:0]  i_ARADDR,
  input  logic [2:0]  i_ARPROT,     // not used
  input  logic        i_ARVALID,
  output logic        o_ARREADY,

  // Read data
  output logic [31:0] o_RDATA,
  output logic [1:0]  o_RRESP,
  output logic        o_RVALID,
  input  logic        i_RREADY
);

  localparam logic [31:0] ID_VALUE    = 32'hA9B0_0001;
  localparam logic [1:0]  RESP_OKAY   = 2'b00;
  localparam logic [1:0]  RESP_SLVERR = 2'b10;

  // Registers: [0] CTRL, [1] DATA0, [2] DATA1
  logic [31:0] r_Regs [0:2];

  // ---------------------------------------------------------------
  // Write path
  // ---------------------------------------------------------------
  logic        r_Aw_Full;           // write address stored, waiting for the data
  logic        r_W_Full;            // write data stored, waiting for the address
  logic [7:0]  r_Aw_Addr;
  logic [31:0] r_W_Data;
  logic [3:0]  r_W_Strb;

  assign o_AWREADY = ~r_Aw_Full;
  assign o_WREADY  = ~r_W_Full;

  wire w_Aw_Hs = i_AWVALID & o_AWREADY;
  wire w_W_Hs  = i_WVALID  & o_WREADY;
  wire w_B_Hs  = o_BVALID  & i_BREADY;

  // Decode the stored write address
  wire [1:0] w_Wr_Index = r_Aw_Addr[3:2];
  wire       w_Wr_Error = (|r_Aw_Addr[7:4]) | (r_Aw_Addr[1:0] != 2'b00) | (w_Wr_Index == 2'd3);

  // Address and data both here, and no response still waiting
  wire       w_Wr_Go    = r_Aw_Full & r_W_Full & ~o_BVALID;

  // Control: flags and BVALID
  always_ff @(posedge i_ACLK) begin
    if (!i_ARESETn) begin
      r_Aw_Full <= 1'b0;
      r_W_Full  <= 1'b0;
      o_BVALID  <= 1'b0;
    end else begin
      if (w_Aw_Hs) r_Aw_Full <= 1'b1;
      if (w_W_Hs)  r_W_Full  <= 1'b1;
      if (w_Wr_Go) o_BVALID  <= 1'b1;
      if (w_B_Hs) begin
        o_BVALID  <= 1'b0;
        r_Aw_Full <= 1'b0;
        r_W_Full  <= 1'b0;
      end
    end
  end

  // Data: stored address, data, strobes and response (no reset needed,
  // they are only used while their flag or BVALID is set)
  always_ff @(posedge i_ACLK) begin
    if (w_Aw_Hs) r_Aw_Addr <= i_AWADDR;
    if (w_W_Hs) begin
      r_W_Data <= i_WDATA;
      r_W_Strb <= i_WSTRB;
    end
    if (w_Wr_Go) o_BRESP <= w_Wr_Error ? RESP_SLVERR : RESP_OKAY;
  end

  // Register file: only the bytes selected by WSTRB are written
  always_ff @(posedge i_ACLK) begin
    if (!i_ARESETn) begin
      r_Regs[0] <= 32'h0;
      r_Regs[1] <= 32'h0;
      r_Regs[2] <= 32'h0;
    end else if (w_Wr_Go && !w_Wr_Error) begin
      for (int b = 0; b < 4; b++)
        if (r_W_Strb[b])
          r_Regs[w_Wr_Index][8*b +: 8] <= r_W_Data[8*b +: 8];
    end
  end

  // ---------------------------------------------------------------
  // Read path
  // ---------------------------------------------------------------
  assign o_ARREADY = ~o_RVALID;

  wire w_Ar_Hs = i_ARVALID & o_ARREADY;
  wire w_R_Hs  = o_RVALID  & i_RREADY;

  // Decode the read address at the AR handshake
  wire [1:0] w_Rd_Index = i_ARADDR[3:2];
  wire       w_Rd_Error = (|i_ARADDR[7:4]) | (i_ARADDR[1:0] != 2'b00);

  // Control: RVALID
  always_ff @(posedge i_ACLK) begin
    if (!i_ARESETn)   o_RVALID <= 1'b0;
    else if (w_Ar_Hs) o_RVALID <= 1'b1;
    else if (w_R_Hs)  o_RVALID <= 1'b0;
  end

  // Data: read data and response, held until the master takes them
  always_ff @(posedge i_ACLK) begin
    if (w_Ar_Hs) begin
      if (w_Rd_Error) begin
        o_RDATA <= 32'h0;
        o_RRESP <= RESP_SLVERR;
      end else begin
        o_RRESP <= RESP_OKAY;
        case (w_Rd_Index)
          2'd0: o_RDATA <= r_Regs[0];
          2'd1: o_RDATA <= r_Regs[1];
          2'd2: o_RDATA <= r_Regs[2];
          2'd3: o_RDATA <= ID_VALUE;
        endcase
      end
    end
  end

endmodule