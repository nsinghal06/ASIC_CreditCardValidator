// Module 1: PAN input stream: 16 digits
// Inputs: start, digit_valid, digit_in[3:0]
//  Outputs:
//  pan_bcd, pan_ready, len_final, card_done, iin_prefix

module pan_stream #(
    parameter integer MIN_LEN    = 16,
    parameter integer MAX_LEN    = 16,
    parameter integer IIN_DIGITS = 6
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start,
    input  logic        pan_end,
    input  logic        digit_valid,
    input  logic [3:0]  digit_in,

    output logic [75:0] pan_bcd,
    output logic        pan_ready,
    output logic        card_done,
    output logic [4:0]  len_final,
    output logic [31:0] iin_prefix
);

    logic        in_progress;
    logic [4:0]  len_count;
    logic [3:0]  iin_digits_captured;

    localparam logic [3:0] IIN_DIGITS4 = IIN_DIGITS[3:0];

    wire accept_digit = in_progress && digit_valid && (len_count < 5'd16);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_progress         <= 1'b0;
            len_count           <= 5'd0;
            len_final           <= 5'd0;

            pan_bcd             <= '0;
            pan_ready           <= 1'b0;
            card_done           <= 1'b0;

            iin_prefix          <= 32'd0;
            iin_digits_captured <= 4'd0;
        end else begin
            // default: pulse outputs low each cycle
            card_done <= 1'b0;

            // Start new card
            if (start) begin
                in_progress         <= 1'b1;
                len_count           <= 5'd0;
                len_final           <= 5'd0;

                pan_bcd             <= '0;
                pan_ready           <= 1'b0;

                iin_prefix          <= 32'd0;
                iin_digits_captured <= 4'd0;
            end

            // Capture digit
            if (accept_digit) begin
                // Store digit in BCD array
                pan_bcd[4*len_count +: 4] <= digit_in;

                // Capture first IIN_DIGITS digits into iin_prefix (nibble-packed)
                if (iin_digits_captured < IIN_DIGITS4) begin
                    iin_prefix[4*iin_digits_captured +: 4] <= digit_in;
                    iin_digits_captured <= iin_digits_captured + 4'd1;
                end

                // increment count
                len_count <= len_count + 5'd1;
            end

            // End of card
            if (pan_end && in_progress) begin
                // include last digit if pan_end coincides with digit_valid (and we still accepted it)
                len_final   <= len_count + ((digit_valid && (len_count < 5'd16)) ? 5'd1 : 5'd0);

                card_done   <= 1'b1;
                pan_ready   <= 1'b1;
                in_progress <= 1'b0;
            end
        end
    end

endmodule