`timescale 1ns/1ps
`default_nettype none

module tb;

  reg  clk;
  reg  rst_n;

  reg  [7:0] ui_in;
  wire [7:0] uo_out;

  reg  [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  reg  ena;

  // Instantiate DUT (CHANGE THIS NAME)
  tt_um_CCValidator dut (
    .ui_in  (ui_in),
    .uo_out (uo_out),
    .uio_in (uio_in),
    .uio_out(uio_out),
    .uio_oe (uio_oe),
    .ena    (ena),
    .clk    (clk),
    .rst_n  (rst_n)
  );

  // Clock generation (10ns period = 100 MHz)
  initial clk = 0;
  always #5 clk = ~clk;

  // Default inputs
  initial begin
    ena   = 1'b1;
    ui_in = 8'h00;
    uio_in = 8'h00;
  end

  // VCD dump
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
  end

endmodule

`default_nettype wire
