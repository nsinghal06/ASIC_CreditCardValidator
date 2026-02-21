`timescale 1ns/1ps
`default_nettype none

module tb;

  reg clk = 0;
  reg rst_n = 0;

  reg start = 0;
  reg pan_end = 0;
  reg digit_valid = 0;
  reg [3:0] digit_in = 0;
  reg abort = 0;

  wire [3:0] s_digit;
  wire s_valid, s_first, s_last;
  wire [4:0] len_count, len_final;
  wire len_parity, length_ok;
  wire [31:0] iin_prefix;
  wire [3:0] iin_digits_captured;
  wire iin_ready;
  wire in_progress, card_done, digit_ok, error_flag;
  wire [75:0] pan_bcd;
  wire pan_ready;

  // 100 MHz clock
  always #5 clk = ~clk;

  pan_stream dut (
    .clk(clk), .rst_n(rst_n),
    .start(start), .pan_end(pan_end),
    .digit_valid(digit_valid), .digit_in(digit_in),
    .abort(abort),

    .s_digit(s_digit), .s_valid(s_valid),
    .s_first(s_first), .s_last(s_last),

    .len_count(len_count), .len_final(len_final),
    .len_parity(len_parity), .length_ok(length_ok),

    .iin_prefix(iin_prefix), .iin_digits_captured(iin_digits_captured),
    .iin_ready(iin_ready),

    .in_progress(in_progress), .card_done(card_done),
    .digit_ok(digit_ok), .error_flag(error_flag),

    .pan_bcd(pan_bcd), .pan_ready(pan_ready)
  );

endmodule

`default_nettype wire