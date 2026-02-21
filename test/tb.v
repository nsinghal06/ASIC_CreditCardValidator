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

    reg  [95:0] nonce_in;
  reg         nonce_valid;

  wire [63:0] token64;
  wire [15:0] token_tag16;
  wire        token_valid;
  wire        token_busy;

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

  wire luhn_valid;
  wire luhn_valid_raw;

  pan_luhn_bridge luhn_bridge (
    .pan_ready(pan_ready),
    .len_final(len_final),
    .pan_bcd(pan_bcd),
    .luhn_valid(luhn_valid),
    .luhn_valid_raw(luhn_valid_raw)
  );

    wire [15:0] prefix4_bcd = iin_prefix[15:0];

  wire [2:0] brand_id;
  wire [4:0] issuer_id;
  wire [1:0] type_id;
  wire meta_hit, meta_valid;

  iin_prefix4_classifier meta_u (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .card_done(card_done),
    .luhn_valid(luhn_valid),
    .prefix4_bcd(prefix4_bcd),
    .brand_id(brand_id),
    .issuer_id(issuer_id),
    .type_id(type_id),
    .meta_hit(meta_hit),
    .meta_valid(meta_valid)
  );

    pan_tokenizer tok_u (
    .clk(clk),
    .rst_n(rst_n),

    .start(start),
    .card_done(card_done),
    .pan_ready(pan_ready),
    .luhn_valid(luhn_valid),
    .len_final(len_final),
    .pan_bcd(pan_bcd),

    .nonce_in(nonce_in),
    .nonce_valid(nonce_valid),

    .token64(token64),
    .token_tag16(token_tag16),
    .token_valid(token_valid),
    .token_busy(token_busy)
  );


endmodule

`default_nettype wire