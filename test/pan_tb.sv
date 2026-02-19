`timescale 1ns/1ps
`default_nettype none

module pan_tb;

  logic clk = 0;
  always #5 clk = ~clk;  // 100 MHz

  logic rst_n;

  logic start, pan_end, abort;
  logic digit_valid;
  logic [3:0] digit_in;

  logic [3:0] s_digit;
  logic s_valid, s_first, s_last;

  logic [4:0] len_final;
  logic len_parity;
  logic length_ok;

  logic [31:0] iin_prefix;
  logic [3:0]  iin_digits_captured;
  logic iin_ready;

  logic digit_ok;
  logic error_flag;

  // DUT
  pan_stream dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .pan_end(pan_end),
    .digit_valid(digit_valid),
    .digit_in(digit_in),
    .abort(abort),

    .s_digit(s_digit),
    .s_valid(s_valid),
    .s_first(s_first),
    .s_last(s_last),

    .len_final(len_final),
    .len_parity(len_parity),
    .length_ok(length_ok),

    .iin_prefix(iin_prefix),
    .iin_digits_captured(iin_digits_captured),
    .iin_ready(iin_ready),

    .digit_ok(digit_ok),
    .error_flag(error_flag)
  );

  task send_digit(input [3:0] d);
    begin
      digit_in    = d;
      digit_valid = 1'b1;
      @(posedge clk);
      digit_valid = 1'b0;
      @(posedge clk);
    end
  endtask

  initial begin
    $dumpfile("pan_tb.vcd");
    $dumpvars(0, pan_tb);

    // init
    rst_n = 0;
    abort = 0;
    start = 0; pan_end = 0;
    digit_valid = 0; digit_in = 0;

    repeat (3) @(posedge clk);
    rst_n = 1;

    // Example PAN with 16 digits: 4 1 1 1 ... (Visa-like start, just for testing length)
    @(posedge clk);
    start = 1; @(posedge clk); start = 0;

    // send 16 digits total
    send_digit(4);
    send_digit(1);
    repeat (14) send_digit(1);

    // end pulse (ideally with last digit_valid; for simplicity we do it right after)
    pan_end = 1; @(posedge clk); pan_end = 0;

    repeat (10) @(posedge clk);
    $finish;
  end

endmodule
