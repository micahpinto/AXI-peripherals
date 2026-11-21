# AXI-peripherals
AXI4-Lite register slave and AXI4-Stream FIFO in SystemVerilog, verified with self-checking testbenches and packaged as Vivado IP for a Spartan-7 FPGA

| Folder | What it is | Verification |
|---|---|---|
| [axi-lite-regs](axi-lite-regs/) | AXI4-Lite slave with 4 registers, byte strobes and SLVERR | directed testbench (25 checks) and random testbench (3 seeds x 2000 transactions) with a register model and 5 handshake assertions |
| [axis-fifo](axis-fifo/) | AXI4-Stream FIFO, 16 bytes, keeps TLAST with each byte | random testbench with a queue model, random backpressure and a handshake assertion |
