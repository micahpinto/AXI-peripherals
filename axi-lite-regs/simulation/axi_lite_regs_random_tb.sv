// Random testbench for axi_lite_regs.
//   - 2000 random reads and writes: random addresses (mostly the four
//     registers, sometimes any address), random data and byte strobes.
//   - Random waits before every VALID and before BREADY / RREADY, so the
//     address and data arrive in any order and the master is sometimes slow.
//   - A model of the registers, written from the register map, predicts
//     every response and every read value.
//   - Assertions check the VALID/READY rule on all five channels.
// The random seed is set from the simulator: in Vivado, add -sv_seed <n> to the simulation options (default seed when nothing is set).

`timescale 1ns/1ps

module axi_lite_regs_random_tb;

  localparam int          NUM_TRANS = 2000;   // how many random transactions
   localparam logic [31:0] ID_VALUE  = 32'hA9B0_0001;
  localparam logic [1:0]  OKAY      = 2'b00;
  localparam logic [1:0]  SLVERR    = 2'b10;

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

  int errors = 0;

  // ---------------------------------------------------------------
  // Assertions: once VALID is 1 and READY is 0, VALID stays 1 and
  // the data does not change until READY
  // ---------------------------------------------------------------
  //  every assertion that fails: count it and print the message
  task automatic assert_failed(input string msg);
    errors++;
    $error("%s", msg);
  endtask

  property p_Aw_Hold;
    @(posedge r_Clk) disable iff (!r_Rst_n)
      (r_Awvalid && !w_Awready) |=> (r_Awvalid && $stable(r_Awaddr));
  endproperty

  property p_W_Hold;
    @(posedge r_Clk) disable iff (!r_Rst_n)
      (r_Wvalid && !w_Wready) |=> (r_Wvalid && $stable(r_Wdata) && $stable(r_Wstrb));
  endproperty

  property p_B_Hold;
    @(posedge r_Clk) disable iff (!r_Rst_n)
      (w_Bvalid && !r_Bready) |=> (w_Bvalid && $stable(w_Bresp));
  endproperty

  property p_Ar_Hold;
    @(posedge r_Clk) disable iff (!r_Rst_n)
      (r_Arvalid && !w_Arready) |=> (r_Arvalid && $stable(r_Araddr));
  endproperty

  property p_R_Hold;
    @(posedge r_Clk) disable iff (!r_Rst_n)
      (w_Rvalid && !r_Rready) |=> (w_Rvalid && $stable(w_Rdata) && $stable(w_Rresp));
  endproperty

  a_Aw_Hold: assert property (p_Aw_Hold) else assert_failed("AW: AWVALID dropped or AWADDR changed before AWREADY");
  a_W_Hold:  assert property (p_W_Hold)  else assert_failed("W: WVALID dropped or WDATA/WSTRB changed before WREADY");
  a_B_Hold:  assert property (p_B_Hold)  else assert_failed("B: BVALID dropped or BRESP changed before BREADY");
  a_Ar_Hold: assert property (p_Ar_Hold) else assert_failed("AR: ARVALID dropped or ARADDR changed before ARREADY");
  a_R_Hold:  assert property (p_R_Hold)  else assert_failed("R: RVALID dropped or RDATA/RRESP changed before RREADY");
  // END OF ASSERTIONS

  // ---------------------------------------------------------------
  // Model of the registers, written from the register map
  // ---------------------------------------------------------------
  logic [31:0] m_Regs [0:2];         // CTRL, DATA0, DATA1

  // Should a write to this address get SLVERR?
  function automatic bit exp_wr_error(input logic [7:0] addr);
    return (addr >= 8'h10) || (addr[1:0] != 2'b00) || (addr == 8'h0C);
  endfunction

  // Should a read from this address get SLVERR?
  function automatic bit exp_rd_error(input logic [7:0] addr);
    return (addr >= 8'h10) || (addr[1:0] != 2'b00);
  endfunction

  // What should a read return?
  function automatic logic [31:0] exp_rd_data(input logic [7:0] addr);
    if (exp_rd_error(addr)) return 32'h0;
    if (addr == 8'h0C)      return ID_VALUE;
    return m_Regs[addr / 4];
  endfunction

  // After a good write: update the model, only the bytes chosen by strb
  function automatic void model_write(input logic [7:0] addr, input logic [31:0] data, input logic [3:0] strb);
    logic [31:0] mask;
    mask = {{8{strb[3]}}, {8{strb[2]}}, {8{strb[1]}}, {8{strb[0]}}};
    m_Regs[addr / 4] = (m_Regs[addr / 4] & ~mask) | (data & mask);
  endfunction

  // ---------------------------------------------------------------
  // Master tasks with random waits
  // ---------------------------------------------------------------
  // Send the write address after a random wait, then wait until the slave takes it
  task automatic send_aw(input logic [7:0] addr);
    repeat ($urandom_range(0, 4)) @(posedge r_Clk);   // master busy 0 to 4 clocks
    r_Awaddr  <= addr;
    r_Awvalid <= 1'b1;
    do @(posedge r_Clk); while (!w_Awready);
    r_Awvalid <= 1'b0;
  endtask

  // Send the write data after a random wait, then wait until the slave takes it
  task automatic send_w(input logic [31:0] data, input logic [3:0] strb);
    repeat ($urandom_range(0, 4)) @(posedge r_Clk);   // master busy 0 to 4 clocks
    r_Wdata  <= data;
    r_Wstrb  <= strb;
    r_Wvalid <= 1'b1;
    do @(posedge r_Clk); while (!w_Wready);
    r_Wvalid <= 1'b0;
  endtask

  // Write: address and data start together, each after its own random wait,
  // so they arrive in any order. Then take the response after a random wait.
  task automatic axi_write(input  logic [7:0]  addr,
                           input  logic [31:0] data,
                           input  logic [3:0]  strb,
                           output logic [1:0]  resp);
    fork
      send_aw(addr);
      send_w(data, strb);
    join
    repeat ($urandom_range(0, 5)) @(posedge r_Clk);   // master busy 0 to 5 clocks
    r_Bready <= 1'b1;
    do @(posedge r_Clk); while (!w_Bvalid);
    resp = w_Bresp;
    r_Bready <= 1'b0;
  endtask

  // Read: send the address after a random wait, then take the data after a random wait
  task automatic axi_read(input  logic [7:0]  addr,
                          output logic [31:0] data,
                          output logic [1:0]  resp);
    repeat ($urandom_range(0, 4)) @(posedge r_Clk);   // master busy 0 to 4 clocks
    r_Araddr  <= addr;
    r_Arvalid <= 1'b1;
    do @(posedge r_Clk); while (!w_Arready);
    r_Arvalid <= 1'b0;
    repeat ($urandom_range(0, 5)) @(posedge r_Clk);   // master busy 0 to 5 clocks
    r_Rready <= 1'b1;
    do @(posedge r_Clk); while (!w_Rvalid);
    data = w_Rdata;
    resp = w_Rresp;
    r_Rready <= 1'b0;
  endtask

  // Mostly the four real registers, sometimes any address (often a bad one)
  function automatic logic [7:0] random_addr();
    if ($urandom_range(0, 9) < 8) return 8'($urandom_range(0, 3) * 4);   // 0x00, 0x04, 0x08 or 0x0C
    return 8'($urandom_range(0, 255));                                    // any address
  endfunction

  // ---------------------------------------------------------------
  // Test
  // ---------------------------------------------------------------
  initial begin
    logic [7:0]  addr;
    logic [31:0] data, got_data, exp_data;
    logic [3:0]  strb;
    logic [1:0]  resp, exp_resp;
   
    m_Regs[0] = 32'h0;               // model starts at the reset values
    m_Regs[1] = 32'h0;
    m_Regs[2] = 32'h0;

    repeat (3) @(posedge r_Clk);
    r_Rst_n <= 1'b1;

    for (int i = 0; i < NUM_TRANS; i++) begin
      addr = random_addr();

      if ($urandom_range(0, 1) == 1) begin
        // ---------- Write ----------
        data     = $urandom();
        strb     = 4'($urandom_range(0, 15));
        exp_resp = exp_wr_error(addr) ? SLVERR : OKAY;             // ask the model first
        axi_write(addr, data, strb, resp);                         // do it on the slave
        if (resp !== exp_resp) begin                               // compare
          errors++;
          $display("FAIL write #%0d addr %h: BRESP %b, expected %b", i, addr, resp, exp_resp);
        end
        if (exp_resp == OKAY) model_write(addr, data, strb);       // update the model

      end else begin
        // ---------- Read ----------
        exp_resp = exp_rd_error(addr) ? SLVERR : OKAY;             // ask the model first (predict)
        exp_data = exp_rd_data(addr);
        axi_read(addr, got_data, resp);                            // do it on the slave
        if (resp !== exp_resp || got_data !== exp_data) begin      // compare
          errors++;
          $display("FAIL read #%0d addr %h: RDATA %h RRESP %b, expected %h %b",
                   i, addr, got_data, resp, exp_data, exp_resp);
        end
      end
    end

    $display("==========================================");
   if (errors == 0) $display("TEST PASSED: %0d random transactions", NUM_TRANS);
    else             $display("TEST FAILED: %0d errors", errors);
    $display("==========================================");
    $finish;
  end

endmodule