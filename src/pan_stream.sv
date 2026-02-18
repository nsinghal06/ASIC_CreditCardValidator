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
    parameter int MIN_LEN   = 13,
    parameter int MAX_LEN   = 19,
    parameter int IIN_DIGITS = 6    // capture first 6 digits 
) (
    input  logic        clk,
    input  logic        rst_n,

    // Host inputs
    input  logic        start,        // 1-cycle pulse: begin new card
    input  logic        pan_end,          // 1-cycle pulse: last digit has been sent
    input  logic        digit_valid,
    input  logic [3:0]  digit_in,     //actual digit/bit value being streamed in
    input  logic        abort,        // optional: cancel card (can tie low)

    // Stream outputs (to Luhn)
    output logic [3:0]  s_digit, //actual digit/bit value being streamed onward
    output logic        s_valid, //high when module is accepting digits
    output logic        s_first,       // pulse on first accepted digit
    output logic        s_last,        // pulse on last accepted digit

    // Length outputs (how many have been recieved/acceptable)
    output logic [4:0]  len_count,     // running count
    output logic [4:0]  len_final,     // how many numbers counter between 13 - 19
    output logic        len_parity,    // parity of final length odd or even: needed for luhn alogrithm
    output logic        length_ok,     // valid length range?

    // IIN capture (to issuer lookup)
    output logic [31:0] iin_prefix,            // 8 digits packed as nibbles
    output logic [3:0]  iin_digits_captured,   // 0..8
    output logic        iin_ready,             // high once enough digits captured

    // Framing / status
    output logic        in_progress,
    output logic        card_done,     // 1-cycle pulse when card finishes
    output logic        digit_ok,      // sticky: all digits were 0..9
    output logic        error_flag     // sticky: protocol / invalid digit errors
);

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

                // Increment length
                len_count <= len_count + 5'd1;

                // Capture first IIN_DIGITS digits into iin_prefix
                if (iin_digits_captured < IIN_DIGITS[3:0]) begin
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
                in_progress <= 1'b0;
            end
        end
    end

    // Derived outputs
    always_comb begin
        len_parity = len_final[0];
        length_ok  = (len_final >= MIN_LEN[4:0]) && (len_final <= MAX_LEN[4:0]);
    end

endmodule
