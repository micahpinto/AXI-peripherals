// axi_lite_regs_tb.sv
// Directed testbench for axi_lite_regs: reset values, writes with the address
// and data in either order, late BREADY/RREADY, error responses and WSTRB.

`timescale 1ns/1ps

module axi_lite_regs_tb;

  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] SLVERR = 2'b10;

  // Clock and reset
  logic r_Clk = 1'b0;
  logic r_Rst_n = 1'b0;
  always #5 r_Clk = ~r_Clk;          // 100 MHz

  // Master side signals
  logic [7:0]  r_Awaddr  = '0;
  logic        r_Awvalid = 1'b0;
  logic [31:0] r_Wdata   = '0;
  logic [3:0]  r_Wstrb   = '0;
  logic        r_Wvalid  = 1'b0;
  logic        r_Bready  = 1'b0;
  logic [7:0]  r_Araddr  = '0;
  logic        r_Arvalid = 1'b0;
  logic        r_Rready  = 1'b0;

  wire         w_Awready;
  wire         w_Wready;
  wire  [1:0]  w_Bresp;
  wire         w_Bvalid;
  wire         w_Arready;
  wire  [31:0] w_Rdata;
  wire  [1:0]  w_Rresp;
  wire         w_Rvalid;

  axi_lite_regs dut (
    .i_ACLK   (r_Clk),
    .i_ARESETn(r_Rst_n),
    .i_AWADDR (r_Awaddr),
    .i_AWPROT (3'b000),
    .i_AWVALID(r_Awvalid),
    .o_AWREADY(w_Awready),
    .i_WDATA  (r_Wdata),
    .i_WSTRB  (r_Wstrb),
    .i_WVALID (r_Wvalid),
    .o_WREADY (w_Wready),
    .o_BRESP  (w_Bresp),
    .o_BVALID (w_Bvalid),
    .i_BREADY (r_Bready),
    .i_ARADDR (r_Araddr),
    .i_ARPROT (3'b000),
    .i_ARVALID(r_Arvalid),
    .o_ARREADY(w_Arready),
    .o_RDATA  (w_Rdata),
    .o_RRESP  (w_Rresp),
    .o_RVALID (w_Rvalid),
    .i_RREADY (r_Rready)
  );

  // Checker
  int errors = 0;

  task automatic check(input string name, input logic [31:0] got, input logic [31:0] expected);
    if (got !== expected) begin
      errors++;
      $display("FAIL  %-34s got %h, expected %h", name, got, expected);
    end else begin
      $display("PASS  %-34s %h", name, got);
    end
  endtask

  // Send the write address and wait until the slave takes it
  task automatic send_aw(input logic [7:0] addr);
    r_Awaddr  <= addr;
    r_Awvalid <= 1'b1;
    do @(posedge r_Clk); while (!w_Awready);
    r_Awvalid <= 1'b0;
  endtask

  // Send the write data and wait until the slave takes it
  task automatic send_w(input logic [31:0] data, input logic [3:0] strb);
    r_Wdata  <= data;
    r_Wstrb  <= strb;
    r_Wvalid <= 1'b1;
    do @(posedge r_Clk); while (!w_Wready);
    r_Wvalid <= 1'b0;
  endtask

  // Write: order 0 = address first, 1 = data first, 2 = both in the same clock.
  // b_wait = clocks to wait before setting BREADY.
  task automatic axi_write(input  logic [7:0]  addr,
                           input  logic [31:0] data,
                           input  logic [3:0]  strb,
                           input  int          order,
                           input  int          b_wait,
                           output logic [1:0]  resp);
    @(posedge r_Clk);
    case (order)
      0: begin send_aw(addr); repeat (2) @(posedge r_Clk); send_w(data, strb); end
      1: begin send_w(data, strb); repeat (2) @(posedge r_Clk); send_aw(addr); end
      default: fork
        send_aw(addr);
        send_w(data, strb);
      join
    endcase
    repeat (b_wait) @(posedge r_Clk);
    r_Bready <= 1'b1;
    do @(posedge r_Clk); while (!w_Bvalid);
    resp = w_Bresp;
    r_Bready <= 1'b0;
  endtask

  // Read: r_wait = clocks to wait before setting RREADY
  task automatic axi_read(input  logic [7:0]  addr,
                          input  int          r_wait,
                          output logic [31:0] data,
                          output logic [1:0]  resp);
    @(posedge r_Clk);
    r_Araddr  <= addr;
    r_Arvalid <= 1'b1;
    do @(posedge r_Clk); while (!w_Arready);
    r_Arvalid <= 1'b0;
    repeat (r_wait) @(posedge r_Clk);
    r_Rready <= 1'b1;
    do @(posedge r_Clk); while (!w_Rvalid);
    data = w_Rdata;
    resp = w_Rresp;
    r_Rready <= 1'b0;
  endtask

  // Tests
  logic [31:0] d;
  logic [1:0]  resp;

  initial begin
    repeat (3) @(posedge r_Clk);

    $display("--- Test 1: during reset");
    check("BVALID", w_Bvalid, 0);
    check("RVALID", w_Rvalid, 0);
    r_Rst_n <= 1'b1;

    $display("--- Test 2: reset values");
    axi_read(8'h00, 0, d, resp);  check("CTRL", d, 0);
    axi_read(8'h04, 0, d, resp);  check("DATA0", d, 0);
    axi_read(8'h08, 0, d, resp);  check("DATA1", d, 0);
    axi_read(8'h0C, 0, d, resp);  check("ID", d, 32'hA9B0_0001);
                                  check("ID response", resp, OKAY);

    $display("--- Test 3: address and data in any order");
    axi_write(8'h00, 32'h1111_1111, 4'hF, 0, 0, resp);  check("CTRL write, address first", resp, OKAY);
    axi_write(8'h04, 32'h2222_2222, 4'hF, 1, 0, resp);  check("DATA0 write, data first", resp, OKAY);
    axi_write(8'h08, 32'h3333_3333, 4'hF, 2, 0, resp);  check("DATA1 write, same clock", resp, OKAY);
    axi_read(8'h00, 0, d, resp);  check("CTRL", d, 32'h1111_1111);
    axi_read(8'h04, 0, d, resp);  check("DATA0", d, 32'h2222_2222);
    axi_read(8'h08, 0, d, resp);  check("DATA1", d, 32'h3333_3333);

    $display("--- Test 4: master slow to take the response");
    axi_write(8'h00, 32'h4444_4444, 4'hF, 0, 3, resp);  check("CTRL write, BREADY late", resp, OKAY);
    axi_read(8'h00, 3, d, resp);  check("CTRL, RREADY late", d, 32'h4444_4444);

    $display("--- Test 5: write errors");
    axi_write(8'h0C, 32'hDEAD_BEEF, 4'hF, 0, 0, resp);  check("write ID", resp, SLVERR);
    axi_write(8'h06, 32'hDEAD_BEEF, 4'hF, 1, 0, resp);  check("write 0x06 (unaligned)", resp, SLVERR);
    axi_write(8'h14, 32'hDEAD_BEEF, 4'hF, 2, 0, resp);  check("write 0x14 (out of range)", resp, SLVERR);
    axi_read(8'h0C, 0, d, resp);  check("ID unchanged", d, 32'hA9B0_0001);
    axi_read(8'h04, 0, d, resp);  check("DATA0 unchanged", d, 32'h2222_2222);

    $display("--- Test 6: byte strobes");
    axi_write(8'h08, 32'hAABB_CCDD, 4'b0101, 0, 0, resp);  check("DATA1 write, WSTRB 0101", resp, OKAY);
    axi_read(8'h08, 0, d, resp);  check("DATA1", d, 32'h33BB_33DD);

    $display("--- Test 7: read errors");
    axi_read(8'h10, 0, d, resp);  check("read 0x10 response", resp, SLVERR);
                                  check("read 0x10 data", d, 0);
    axi_read(8'h0A, 0, d, resp);  check("read 0x0A response", resp, SLVERR);

    $display("==========================================");
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d errors", errors);
    $display("==========================================");
    $finish;
  end

endmodule