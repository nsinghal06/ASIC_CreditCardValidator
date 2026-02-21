// Module 1: PAN input stream: 16 digits
// What it does:
// - Receives a stream of digits (0..9) with digit_valid
// - start = 1-cycle pulse to begin a new PAN
// - end   = 1-cycle pulse to finish the PAN (ideally asserted with the last digit_valid)
// - Counts digits (length), captures IIN prefix (first 8 digits), and streams digits out
//
//  Outputs:
// - card_done (pulse when end received)
// - len_final and length_ok
// - iin_prefix and iin_ready
// - error_flag if protocol is weird (e.g., end without digit_valid)

module pan_stream #(
    parameter integer MIN_LEN    = 13,
    parameter integer MAX_LEN    = 19,
    parameter integer IIN_DIGITS = 6
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start,
    input  logic        pan_end,
    input  logic        digit_valid,
    input  logic [3:0]  digit_in,
    input  logic        abort,

    output logic [3:0]  s_digit,
    output logic        s_valid,
    output logic        s_first,
    output logic        s_last,

    output logic [4:0]  len_count,
    output logic [4:0]  len_final,
    output logic        len_parity,
    output logic        length_ok,

    output logic [31:0] iin_prefix,
    output logic [3:0]  iin_digits_captured,
    output logic        iin_ready,

    output logic        in_progress,
    output logic        card_done,
    output logic        digit_ok,
    output logic        error_flag,

    output logic [75:0] pan_bcd,     // up to 19 digits * 4 bits
    output logic        pan_ready    // 1 when card_done and data latched

);

    localparam logic [4:0] MIN_LEN5    = MIN_LEN;
    localparam logic [4:0] MAX_LEN5    = MAX_LEN;
    localparam logic [3:0] IIN_DIGITS4 = IIN_DIGITS;
    // Accept digits only while in_progress
    //logic replaces reg/wire: is simpler because can be used in alwyas block 
    logic accept_digit;
    assign accept_digit = in_progress && digit_valid;

    // Forward digit stream (gated)
    //sv version of always@(*) combinational block
    always_comb begin
        s_digit = digit_in;
        s_valid = accept_digit;
    end

    // Sequential state
    //updated ff on every pos edge
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
           //reset states
            in_progress         <= 1'b0; 
            len_count           <= 5'd0;
            len_final           <= 5'd0;

            iin_prefix          <= 32'd0;
            iin_digits_captured <= 4'd0;
            iin_ready           <= 1'b0;

            s_first             <= 1'b0;
            s_last              <= 1'b0;
            card_done           <= 1'b0;

            digit_ok            <= 1'b1;
            error_flag          <= 1'b0;
            pan_bcd   <= '0;
            pan_ready <= 1'b0;
        end 
        
        else begin
            // default pulses low each cycle
            s_first   <= 1'b0;
            s_last    <= 1'b0;
            card_done <= 1'b0;

            // Start a new PAN
            //set to 0 at start of every clk, when digit is sent, set pulse to 1
            if (start) begin
                in_progress         <= 1'b1; //actively accepting digits
                len_count           <= 5'd0; //start count from 0
                len_final           <= 5'd0; 

                iin_prefix          <= 32'd0; //clear IIN
                iin_digits_captured <= 4'd0;
                iin_ready           <= 1'b0;

                digit_ok            <= 1'b1; //assume digit ok until error
                error_flag          <= 1'b0;   // clear errors for new card
                pan_bcd   <= '0;
                pan_ready <= 1'b0;
            end

            // Abort cancels the current PAN
            if (abort && in_progress) begin
                in_progress <= 1'b0;
                error_flag  <= 1'b1;
            end

            // Accept a digit
            if (accept_digit) begin
                // First digit pulse
                if (len_count == 5'd0) begin
                    s_first <= 1'b1;
                end

                // Digit validity check
                if (digit_in > 4'd9) begin
                    digit_ok   <= 1'b0;
                    error_flag <= 1'b1;
                end

                pan_bcd[4*len_count +: 4] <= digit_in;

                // Increment length
                len_count <= len_count + 5'd1;

                // Capture first IIN_DIGITS digits into iin_prefix
                if (iin_digits_captured < IIN_DIGITS4) begin
                    iin_prefix <= (iin_prefix & ~(32'hF << (4*iin_digits_captured))) |
                                  ({28'd0, digit_in} << (4*iin_digits_captured));
                    iin_digits_captured <= iin_digits_captured + 4'd1;

                    // Mark ready after at least 6 digits (adjust if you want 8)
                    if (iin_digits_captured + 4'd1 >= 4'd6)
                        iin_ready <= 1'b1;
                end
            end

            // End-of-card handling
            // Assumption: end is asserted on the same cycle as the last digit_valid.
            if (pan_end && in_progress) begin
                if (digit_valid) begin
                    s_last <= 1'b1;
                end else begin
                    // end without digit_valid is odd; flag it
                    error_flag <= 1'b1;
                end

                // Latch final length:
                // If end coincides with digit_valid, final length should include that digit.
                len_final   <= len_count + (digit_valid ? 5'd1 : 5'd0);

                card_done   <= 1'b1;
                pan_ready <= 1'b1;
                in_progress <= 1'b0;
            end
        end
    end

    // Derived outputs
    always_comb begin
        len_parity = len_final[0];
        length_ok  = (len_final >= MIN_LEN5) && (len_final <= MAX_LEN5);
    end

endmodule
