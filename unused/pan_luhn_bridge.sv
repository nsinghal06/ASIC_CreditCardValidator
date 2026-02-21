`default_nettype none

module pan_luhn_bridge (
    input  logic        pan_ready,
    input  logic [4:0]  len_final,   // keep if other code expects it (or remove later)
    input  logic [75:0] pan_bcd,
    output logic        luhn_valid
);

    logic [3:0] digit_arr [15:0];
    logic       valid_raw;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : MAP
            assign digit_arr[i] = pan_bcd[4*(15 - i) +: 4];
        end
    endgenerate

    luhn_validator U_LUHN (
        .digit(digit_arr),
        .valid(valid_raw)
    );

    always_comb begin
        luhn_valid = pan_ready ? valid_raw : 1'b0;
    end

endmodule

`default_nettype wire