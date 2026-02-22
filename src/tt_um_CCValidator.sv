/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_CCValidator (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

   
  wire [3:0] digit_in    = ui_in[3:0];
  wire       digit_valid = ui_in[4];
  wire       start       = ui_in[5];
  wire       pan_end     = ui_in[6];

  wire [75:0] pan_bcd;
  wire        pan_ready;
  wire        card_done;
  wire [4:0]  len_final;
  wire [31:0] iin_prefix;

  pan_stream u_stream (
    .clk      (clk),
    .rst_n    (rst_n),
    .start    (start),
    .pan_end  (pan_end),
    .digit_valid(digit_valid),
    .digit_in (digit_in),
    .pan_bcd  (pan_bcd),
    .pan_ready(pan_ready),
    .card_done(card_done),
    .len_final(len_final),
    .iin_prefix(iin_prefix)
  );

  

    wire luhn_valid_raw;
    luhn_validator u_luhn (
    .pan_ready(pan_ready),
    .pan_bcd(pan_bcd),
    .valid(luhn_valid_raw)
    );

  wire len16 = (len_final === 5'd16);   // '===' returns 0 if len_final has any 
  wire luhn_valid = len16 ? luhn_valid_raw : 1'b0;

  wire [15:0] prefix4_bcd = iin_prefix[15:0];

  wire [2:0] brand_id;
  wire [4:0] issuer_id;
  wire [1:0] type_id;
  wire meta_hit, meta_valid;

  iin_prefix4_classifier u_meta (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (start),
    .card_done  (card_done),
    .luhn_valid (luhn_valid),
    .prefix4_bcd(prefix4_bcd),
    .brand_id   (brand_id),
    .issuer_id  (issuer_id),
    .type_id    (type_id),
    .meta_hit   (meta_hit),
    .meta_valid (meta_valid)
  );

  reg [95:0] nonce_ctr;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) nonce_ctr <= 96'd0;
    else if (start) nonce_ctr <= nonce_ctr + 96'd1;
  end
  wire [95:0] nonce_in    = nonce_ctr;
  wire        nonce_valid = start;

  wire [63:0] token64;
  wire [15:0] token_tag16;
  wire        token_valid;
  wire        token_busy;

  pan_encryptor u_tok (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (start),
    .card_done  (card_done),
    .pan_ready  (pan_ready),
    .luhn_valid (luhn_valid),
    .len_final  (len_final),
    .pan_bcd    (pan_bcd),
    .nonce_in   (nonce_in),
    .nonce_valid(nonce_valid),
    .token64    (token64),
    .token_tag16(token_tag16),
    .token_valid(token_valid),
    .token_busy (token_busy)
  );

  reg  [63:0] token_latched;
  reg  [2:0]  byte_idx;
  reg         stream_active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      token_latched <= 64'd0;
      byte_idx      <= 3'd0;
      stream_active <= 1'b0;
    end else begin
      if (start) begin
        byte_idx      <= 3'd0;
        stream_active <= 1'b0;
      end else if (!stream_active && token_valid) begin
        token_latched <= token64;
        byte_idx      <= 3'd0;
        stream_active <= 1'b1;
      end else if (stream_active) begin
        if (byte_idx == 3'd7) begin
          stream_active <= 1'b0;
        end else begin
          byte_idx <= byte_idx + 3'd1;
        end
      end
    end
  end

  wire [7:0] token_byte = token_latched[8*byte_idx +: 8];

  assign uo_out = stream_active ? token_byte : 8'h00;

  assign uio_oe  = 8'hFF;
  assign uio_out = (!rst_n) ? 8'h00 : {
    token_busy,      // directly from pan_encryptor
    meta_valid,      // directly from classifier
    meta_hit,        // directly from classifier
    luhn_valid,      // directly from luhn_validator
    stream_active,   // from the always_ff block
    byte_idx         // from the always_ff block
};
  wire _unused = &{ui_in[7], uio_in[7:0], ena, brand_id, issuer_id, type_id, token_tag16, 1'b0};

endmodule

`default_nettype wire