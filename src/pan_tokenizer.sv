`default_nettype none

module pan_tokenizer (
    input  logic        clk,
    input  logic        rst_n,

    // From pan_stream / luhn
    input  logic        start,       // start of new card (clears outputs)
    input  logic        card_done,    // 1-cycle pulse when PAN capture ends
    input  logic        pan_ready,    // latched 1 when PAN is available
    input  logic        luhn_valid,   // 1 if checksum passes
    input  logic [4:0]  len_final,    // final length
    input  logic [75:0] pan_bcd,      // digit0 in [3:0], digit1 in [7:4], ... up to 19 digits

    // Nonce inputs (for demo). You can change this later.
    input  logic [95:0] nonce_in,
    input  logic        nonce_valid,  // pulse if you want to load a new nonce; optional

    // Outputs
    output logic [63:0] token64,      // internal token (useful in sim)
    output logic [15:0] token_tag16,  // small demo output
    output logic        token_valid,  // goes 1 when token_tag16 is ready
    output logic        token_busy    // 1 while chacha is running
);

    // Select the 16-digit PAN portion (64 bits)
    logic [63:0] pan16_bcd;
    assign pan16_bcd = pan_bcd[63:0];

    // Nonce register 
    logic [95:0] nonce_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nonce_reg <= 96'd0;
        end else begin
            if (start) begin
                // optional: clear/keep
                nonce_reg <= nonce_reg;
            end
            if (nonce_valid) begin
                nonce_reg <= nonce_in;
            end
        end
    end

    // ChaCha control
    logic        chacha_enable;
    logic [511:0] chacha_block;
    logic        chacha_ready;

    // Simple FSM for tokenization
    typedef enum logic [1:0] { T_IDLE=2'd0, T_RUN=2'd1, T_DONE=2'd2 } tok_state_t;
    tok_state_t tstate;

    // start ChaCha only when: card finished + pan available + luhn ok + 16 digits
    logic want_token;
    assign want_token = card_done && pan_ready && luhn_valid && (len_final == 5'd16);

    // enable is a pulse when we enter RUN
    always_comb begin
        chacha_enable = 1'b0;
        if (tstate == T_IDLE && want_token) begin
            chacha_enable = 1'b1;
        end
    end

    // Instantiate ChaCha core (ready is 1-cycle pulse)
    chacha20core u_chacha (
        .clk    (clk),
        .resetn (rst_n),       // note: your chacha uses resetn (active-low)
        .enable (chacha_enable),
        .nonce  (nonce_reg),
        .cipher (chacha_block),
        .ready  (chacha_ready)
    );

    // Busy flag
    always_comb begin
        token_busy = (tstate == T_RUN);
    end

    // Token computation + latching
    logic [63:0] ks64;
    assign ks64 = chacha_block[63:0]; // take lowest 64 bits as keystream

    // fold 64 -> 16 bits (XOR reduction)
    function automatic [15:0] fold64to16(input [63:0] x);
        fold64to16 = x[15:0] ^ x[31:16] ^ x[47:32] ^ x[63:48];
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tstate      <= T_IDLE;
            token64     <= 64'd0;
            token_tag16 <= 16'd0;
            token_valid <= 1'b0;
        end else begin
            // default
            token_valid <= 1'b0;

            if (start) begin
                // clear outputs for new card
                tstate      <= T_IDLE;
                token64     <= 64'd0;
                token_tag16 <= 16'd0;
                token_valid <= 1'b0;
            end else begin
                case (tstate)
                    T_IDLE: begin
                        // wait for want_token, then chacha_enable pulses automatically
                        if (want_token) begin
                            tstate <= T_RUN;
                        end
                    end

                    T_RUN: begin
                        if (chacha_ready) begin
                            // token = PAN xor keystream
                            token64     <= pan16_bcd ^ ks64;
                            token_tag16 <= fold64to16(pan16_bcd ^ ks64);
                            token_valid <= 1'b1;  // pulse
                            tstate      <= T_DONE;
                        end
                    end

                    T_DONE: begin
                        // stay done until next start
                        tstate <= T_DONE;
                    end

                    default: tstate <= T_IDLE;
                endcase
            end
        end
    end

endmodule

`default_nettype wire