`timescale 1ns/1ps
// Synchronous FIFO, method A: a count register gives full and empty.
// Copied from my synchronous-fifo repository, with a synchronous active-low
// reset added so the FIFO can be emptied while running.
module fifo_count #(
  parameter int WIDTH = 8,     // bits per slot
  parameter int DEPTH = 16     // number of slots
)(
  input  logic             i_Clk,
  input  logic             i_Rst_n,    // 0 = empty the FIFO
  // write side
  input  logic             i_Wr_En,
  input  logic [WIDTH-1:0] i_Wr_Data,
  // read side
  input  logic             i_Rd_En,
  output logic [WIDTH-1:0] o_Rd_Data,
  // status
  output logic             o_Empty,
  output logic             o_Full
);

  localparam int PTR_W = $clog2(DEPTH);       // 16 slots - 4-bit pointers

  // ---------- storage ----------
  logic [WIDTH-1:0] r_Mem [DEPTH];
  logic [PTR_W-1:0] r_Wr_Ptr;                 // where the next byte goes
  logic [PTR_W-1:0] r_Rd_Ptr;                 // the oldest byte
  logic [PTR_W:0]   r_Count;                  // 0..DEPTH - one bit wider than a pointer

  // ---------- safety rules ----------
  logic w_Wr, w_Rd;
  assign w_Wr = i_Wr_En && !o_Full;           // never write when full
  assign w_Rd = i_Rd_En && !o_Empty;          // never read when empty

  // ---------- memory (no reset needed) ----------
  always_ff @(posedge i_Clk) begin
    if (w_Wr)
      r_Mem[r_Wr_Ptr] <= i_Wr_Data;
  end

  // ---------- pointers and count ----------
  always_ff @(posedge i_Clk) begin
    if (!i_Rst_n) begin
      r_Wr_Ptr <= '0;
      r_Rd_Ptr <= '0;
      r_Count  <= '0;
    end else begin
      if (w_Wr) r_Wr_Ptr <= r_Wr_Ptr + 1'b1;  // wraps 15 to 0
      if (w_Rd) r_Rd_Ptr <= r_Rd_Ptr + 1'b1;

      case ({w_Wr, w_Rd})
        2'b10:   r_Count <= r_Count + 1'b1;   // write only
        2'b01:   r_Count <= r_Count - 1'b1;   // read only
        default: ;                            // both or neither: no change
      endcase
    end
  end

  // ---------- outputs ----------
  assign o_Rd_Data = r_Mem[r_Rd_Ptr];         // front byte, always visible
  assign o_Empty   = (r_Count == 0);
  assign o_Full    = (r_Count == DEPTH);

endmodule