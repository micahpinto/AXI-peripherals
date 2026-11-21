// Random testbench for axis_fifo.
//   - The testbench is the sender on the S side and the receiver on the M side.
//   - Sender: packets of 1 to 8 bytes (TLAST on the last byte), random gaps.
//   - Receiver: random TREADY (backpressure).
//   - Three phases: slow receiver (FIFO fills), fast receiver (FIFO drains),
//     then balanced; at the end the FIFO is drained.
//   - A queue remembers every byte that went in; every byte that comes out
//     is compared with the front of the queue.
//   - An assertion checks that the output holds TVALID, TDATA and TLAST until TREADY.
// The testbench acts at the falling edge, the FIFO at the rising edge.

`timescale 1ns/1ps

module axis_fifo_tb;

  localparam int DATA_W = 8;
  localparam int DEPTH  = 4;          
  localparam int CYCLES = 6000;       // length of the random test (3 phases)

  // Clock and reset
  logic r_Clk = 1'b0;
  logic r_Rst_n = 1'b0;
  always #5 r_Clk = ~r_Clk;           // 100 MHz

  // Sender side (S)
  logic              r_S_Tvalid = 1'b0;
  logic [DATA_W-1:0] r_S_Tdata  = '0;
  logic              r_S_Tlast  = 1'b0;
  wire               w_S_Tready;

  // Receiver side (M)
  logic              r_M_Tready = 1'b0;
  wire               w_M_Tvalid;
  wire  [DATA_W-1:0] w_M_Tdata;
  wire               w_M_Tlast;

  axis_fifo #(
    .DATA_W(DATA_W),
    .DEPTH (DEPTH)
  ) dut (
    .i_ACLK    (r_Clk),
    .i_ARESETn (r_Rst_n),
    .i_S_TVALID(r_S_Tvalid),
    .o_S_TREADY(w_S_Tready),
    .i_S_TDATA (r_S_Tdata),
    .i_S_TLAST (r_S_Tlast),
    .o_M_TVALID(w_M_Tvalid),
    .i_M_TREADY(r_M_Tready),
    .o_M_TDATA (w_M_Tdata),
    .o_M_TLAST (w_M_Tlast)
  );

  int errors = 0;

  // ---------------------------------------------------------------
  // Assertion: once M_TVALID is 1 and M_TREADY is 0, M_TVALID stays 1
  // and M_TDATA / M_TLAST do not change until M_TREADY
  // ---------------------------------------------------------------
  property p_M_Hold;
    @(posedge r_Clk) disable iff (!r_Rst_n)
      (w_M_Tvalid && !r_M_Tready) |=> (w_M_Tvalid && $stable(w_M_Tdata) && $stable(w_M_Tlast));
  endproperty

  a_M_Hold: assert property (p_M_Hold) else begin
    errors++;
    $error("M: TVALID dropped or TDATA/TLAST changed before TREADY");
  end
  // END OF ASSERTIONS

  // ---------------------------------------------------------------
  // Model: every byte that went in, with its TLAST, oldest first
  // ---------------------------------------------------------------
  logic [DATA_W:0] model [$];         // {TLAST, data}

  // Counters
  int n_In = 0, n_Out = 0, n_Packets = 0, n_Full = 0, n_Empty = 0;

  // Sender state
  int                r_Left = 0;      // bytes still to send in the current packet
  logic [DATA_W-1:0] r_Next = '0;     // value of the next byte (counts up)
  bit                r_S_Taken = 1'b1;  // the byte on S was taken at the last rising edge

  // ---------------------------------------------------------------
  // One clock: drive new inputs, check the FIFO, update the model.
  // p_send: chance (%) that the sender offers a byte
  // p_take: chance (%) that the receiver is ready
  // ---------------------------------------------------------------
  task automatic step(input int p_send, input int p_take);
    bit              s_hs, m_hs;
    logic [DATA_W:0] exp_Slot;        // the byte the model expects at the front

    @(negedge r_Clk);                 // middle of the clock: everything is stable

    // 1. Sender: a new byte only if the last one was taken (or nothing was offered)
    if (r_S_Taken || !r_S_Tvalid) begin
      if ($urandom_range(0, 99) < p_send) begin
        if (r_Left == 0) r_Left = $urandom_range(1, 8);   // start a new packet
        r_S_Tvalid = 1'b1;
        r_S_Tdata  = r_Next;
        r_S_Tlast  = (r_Left == 1);                      // last byte of the packet
        r_Next     = r_Next + 1'b1;
        r_Left     = r_Left - 1;
      end else begin
        r_S_Tvalid = 1'b0;
      end
    end

    // 2. Receiver: ready or not, at random
    r_M_Tready = ($urandom_range(0, 99) < p_take);

    // 3. Check the FIFO against the model
    if (w_S_Tready !== (model.size() < DEPTH)) begin
      errors++;
      $display("%0t: S_TREADY = %b, model holds %0d", $time, w_S_Tready, model.size());
    end
    if (w_M_Tvalid !== (model.size() > 0)) begin
      errors++;
      $display("%0t: M_TVALID = %b, model holds %0d", $time, w_M_Tvalid, model.size());
    end
    if (w_M_Tvalid && model.size() > 0) begin
      exp_Slot = model[0];
      if ({w_M_Tlast, w_M_Tdata} !== exp_Slot) begin
        errors++;
        $display("%0t: out TLAST %b data %h, expected TLAST %b data %h",
                 $time, w_M_Tlast, w_M_Tdata, exp_Slot[DATA_W], exp_Slot[DATA_W-1:0]);
      end
    end

    // 4. Which transfers will happen at the next rising edge
    s_hs = r_S_Tvalid && w_S_Tready;
    m_hs = w_M_Tvalid && r_M_Tready;

    // Counters
    if (!w_S_Tready) n_Full++;
    if (!w_M_Tvalid) n_Empty++;
    if (s_hs)        n_In++;
    if (m_hs)        n_Out++;
    if (m_hs && w_M_Tlast) n_Packets++;

    // 5. Model: what the FIFO will hold after the next rising edge
    if (m_hs) void'(model.pop_front());
    if (s_hs) model.push_back({r_S_Tlast, r_S_Tdata});

    r_S_Taken = s_hs;
  endtask

  initial begin
    // Reset: nothing may come out
    repeat (2) @(negedge r_Clk);
    if (w_M_Tvalid !== 1'b0) begin
      errors++;
      $display("M_TVALID = %b during reset, expected 0", w_M_Tvalid);
    end
    r_Rst_n = 1'b1;

    // Three phases
    for (int i = 0; i < CYCLES; i++) begin
      case ((i * 3) / CYCLES)
        0:       step(90, 20);        // slow receiver: the FIFO fills up
        1:       step(20, 90);        // fast receiver: the FIFO drains
        default: step(50, 50);        // balanced
      endcase
    end

    // Finish the current packet, then drain the FIFO
    while (r_Left > 0) step(100, 50);
    repeat (DEPTH + 5) step(0, 100);
    if (model.size() != 0 || w_M_Tvalid) begin
      errors++;
      $display("FIFO not empty after draining: model holds %0d", model.size());
    end

    $display("------------------------------------------");
    $display("Bytes in: %0d, bytes out: %0d, packets out: %0d", n_In, n_Out, n_Packets);
    $display("Clocks full: %0d, clocks empty: %0d", n_Full, n_Empty);
    $display("==========================================");
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d errors", errors);
    $display("==========================================");
    $finish;
  end

  // Stop if the test gets stuck (for example the FIFO never accepts a byte)
  initial begin
    #1ms;
    $display("TEST FAILED: timeout");
    $finish;
  end

endmodule