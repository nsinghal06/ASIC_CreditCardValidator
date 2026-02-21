/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_CCValidator (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  wire rst;
  wire [9:0] clk_per_bit;

  assign clk_per_bit = {uio_in[7:0], 2'b00}; // set upper 8 bits
  
  
  assign rst = ~rst_n;
  assign uio_oe = 8'b0000_0000; // set bidirectional as inputs
  assign uio_out = 8'b0000_0000; // set unused bidirectional outputs to LOW
  assign uo_out[7:3] = 5'b0_0000; // set unused outputs to LOW

  simproc_system #(
     .CLK_BITS(10)
  ) U1 (
      .clk(clk),
      .rst(rst),

      .clk_per_bit(clk_per_bit),
      .uart_rx(ui_in[0]),

      .uart_tx(uo_out[0]),

      .halt(uo_out[1]),
      .done(uo_out[2])
  );

  // List all unused inputs to prevent warnings
  wire _unused = &{ui_in[7:1], ena, 1'b0};

endmodule
