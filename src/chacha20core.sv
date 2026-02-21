`default_nettype none

module chacha20core (
    input  logic        clk,
    input  logic        resetn,    // active-low reset
    input  logic        enable,    // start pulse/level (only sampled in IDLE)
    input  logic [95:0] nonce,

    output logic [511:0] cipher,   // 16x32-bit block (keystream block style)
    output logic        ready      // 1-cycle pulse when DONE
);
    // State words
    logic [31:0] init [0:15];   // initial state (constants+key+counter+nonce)
    logic [31:0] s    [0:15];   // working state (mutated by rounds)

    // FSM
    typedef enum logic [1:0] { IDLE=2'd0, COL=2'd1, DIAG=2'd2, DONE=2'd3 } fsm_t;
    fsm_t state_fsm;

    logic        phase;         // 0 = column mapping, 1 = diagonal mapping (mainly for clarity)
    logic [3:0]  round_ctr;     // counts double-rounds: 0..9

    // Quarter round wiring (4 lanes)
    logic [31:0] qr0_a_in, qr0_b_in, qr0_c_in, qr0_d_in;
    logic [31:0] qr1_a_in, qr1_b_in, qr1_c_in, qr1_d_in;
    logic [31:0] qr2_a_in, qr2_b_in, qr2_c_in, qr2_d_in;
    logic [31:0] qr3_a_in, qr3_b_in, qr3_c_in, qr3_d_in;

    logic [31:0] qr0_a, qr0_b, qr0_c, qr0_d;
    logic [31:0] qr1_a, qr1_b, qr1_c, qr1_d;
    logic [31:0] qr2_a, qr2_b, qr2_c, qr2_d;
    logic [31:0] qr3_a, qr3_b, qr3_c, qr3_d;

    QRfunction round0(qr0_a_in, qr0_b_in, qr0_c_in, qr0_d_in, qr0_a, qr0_b, qr0_c, qr0_d);
    QRfunction round1(qr1_a_in, qr1_b_in, qr1_c_in, qr1_d_in, qr1_a, qr1_b, qr1_c, qr1_d);
    QRfunction round2(qr2_a_in, qr2_b_in, qr2_c_in, qr2_d_in, qr2_a, qr2_b, qr2_c, qr2_d);
    QRfunction round3(qr3_a_in, qr3_b_in, qr3_c_in, qr3_d_in, qr3_a, qr3_b, qr3_c, qr3_d);

    // Select inputs to the 4 QRs based on phase
    // phase=0: column round
    // phase=1: diagonal round
    always_comb begin
        if (!phase) begin
            // Column: (0,4,8,12) (1,5,9,13) (2,6,10,14) (3,7,11,15)
            qr0_a_in = s[0];  qr0_b_in = s[4];  qr0_c_in = s[8];  qr0_d_in = s[12];
            qr1_a_in = s[1];  qr1_b_in = s[5];  qr1_c_in = s[9];  qr1_d_in = s[13];
            qr2_a_in = s[2];  qr2_b_in = s[6];  qr2_c_in = s[10]; qr2_d_in = s[14];
            qr3_a_in = s[3];  qr3_b_in = s[7];  qr3_c_in = s[11]; qr3_d_in = s[15];
        end else begin
            // Diagonal: (0,5,10,15) (1,6,11,12) (2,7,8,13) (3,4,9,14)
            qr0_a_in = s[0];  qr0_b_in = s[5];  qr0_c_in = s[10]; qr0_d_in = s[15];
            qr1_a_in = s[1];  qr1_b_in = s[6];  qr1_c_in = s[11]; qr1_d_in = s[12];
            qr2_a_in = s[2];  qr2_b_in = s[7];  qr2_c_in = s[8];  qr2_d_in = s[13];
            qr3_a_in = s[3];  qr3_b_in = s[4];  qr3_c_in = s[9];  qr3_d_in = s[14];
        end
    end

    // Output packing
    logic [31:0] outw [0:15];
    integer j;

    always_comb begin
        for (j = 0; j < 16; j++) begin
            outw[j] = s[j] + init[j];
        end

        cipher = {
            outw[0],  outw[1],  outw[2],  outw[3],
            outw[4],  outw[5],  outw[6],  outw[7],
            outw[8],  outw[9],  outw[10], outw[11],
            outw[12], outw[13], outw[14], outw[15]
        };
    end

    // FSM / state update
    integer k;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state_fsm <= IDLE;
            phase     <= 1'b0;
            round_ctr <= 4'd0;
            ready     <= 1'b0;

            // clear state regs (not strictly required, but nice)
            for (k = 0; k < 16; k++) begin
                init[k] <= 32'd0;
                s[k]    <= 32'd0;
            end
        end else begin
            ready <= 1'b0; // default: pulse only in DONE

            case (state_fsm)
                IDLE: begin
                    phase     <= 1'b0;
                    round_ctr <= 4'd0;

                    if (enable) begin
                        // Load initial state = constants + key + counter + nonce
                        init[0]  <= 32'h61707865;
                        init[1]  <= 32'h3320646e;
                        init[2]  <= 32'h79622d32;
                        init[3]  <= 32'h6b206574;

                        // Demo master key (fixed)
                        init[4]  <= 32'hf9d7e836;
                        init[5]  <= 32'h5065c10a;
                        init[6]  <= 32'h784bde64;
                        init[7]  <= 32'ha57b0853;
                        init[8]  <= 32'hae7c8013;
                        init[9]  <= 32'h1b75c64d;
                        init[10] <= 32'hb42931dd;
                        init[11] <= 32'h9df6b36f;

                        // Counter + nonce
                        init[12] <= 32'd0;            // block counter = 0 for demo
                        init[13] <= nonce[95:64];
                        init[14] <= nonce[63:32];
                        init[15] <= nonce[31:0];

                        // Working state starts as init
                        for (k = 0; k < 16; k++) begin
                            s[k] <= init[k];
                        end

                        state_fsm <= COL;
                        phase     <= 1'b0;
                    end
                end

                COL: begin
                    // write back column QR outputs
                    s[0]  <= qr0_a; s[4]  <= qr0_b; s[8]  <= qr0_c; s[12] <= qr0_d;
                    s[1]  <= qr1_a; s[5]  <= qr1_b; s[9]  <= qr1_c; s[13] <= qr1_d;
                    s[2]  <= qr2_a; s[6]  <= qr2_b; s[10] <= qr2_c; s[14] <= qr2_d;
                    s[3]  <= qr3_a; s[7]  <= qr3_b; s[11] <= qr3_c; s[15] <= qr3_d;

                    phase     <= 1'b1;
                    state_fsm <= DIAG;
                end

                DIAG: begin
                    // write back diagonal QR outputs
                    s[0]  <= qr0_a; s[5]  <= qr0_b; s[10] <= qr0_c; s[15] <= qr0_d;
                    s[1]  <= qr1_a; s[6]  <= qr1_b; s[11] <= qr1_c; s[12] <= qr1_d;
                    s[2]  <= qr2_a; s[7]  <= qr2_b; s[8]  <= qr2_c; s[13] <= qr2_d;
                    s[3]  <= qr3_a; s[4]  <= qr3_b; s[9]  <= qr3_c; s[14] <= qr3_d;

                    phase <= 1'b0;

                    if (round_ctr == 4'd9) begin
                        state_fsm <= DONE;     // 10 double-rounds complete
                    end else begin
                        round_ctr <= round_ctr + 4'd1;
                        state_fsm <= COL;
                    end
                end

                DONE: begin
                    ready     <= 1'b1;  // pulse
                    state_fsm <= IDLE;
                end

                default: state_fsm <= IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire