`default_nettype none

module pan_luhn_bridge (
    input  logic        pan_ready,     // from pan_stream
    input  logic [4:0]  len_final,      // from pan_stream
    input  logic [75:0] pan_bcd,        // from pan_stream (digit0 at [3:0], digit1 at [7:4], ...)
    output logic        luhn_valid,     // gated result
    output logic        luhn_valid_raw  // raw luhn output (debug)
);

    // luhn_validator expects: digit[0] = rightmost, digit[15] = leftmost
    logic [3:0] digit_arr [15:0];

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : MAP
            // pan_bcd stores leftmost at index 0; reverse for Luhn
            assign digit_arr[i] = pan_bcd[4*(15 - i) +: 4];
        end
    endgenerate

    luhn_validator U_LUHN (
        .digit(digit_arr),
        .valid(luhn_valid_raw)
    );

    // Only claim a valid result when a full 16-digit PAN is captured
    always_comb begin
        if (pan_ready && (len_final == 5'd16))
            luhn_valid = luhn_valid_raw;
        else
            luhn_valid = 1'b0;
    end

endmodule

`default_nettype wire