module chacha20core(resetn, clk, nonce, cipher, ready, enable);

    input [95:0] nonce; 
    input clk, resetn, enable;
    output logic [511:0] cipher; 
    output reg ready;

    logic [31:0] state [0:15]; //state matrix

    //quarter round inputs
    wire [31:0] qr0_a_in, qr0_b_in, qr0_c_in, qr0_d_in;
    wire [31:0] qr1_a_in, qr1_b_in, qr1_c_in, qr1_d_in;
    wire [31:0] qr2_a_in, qr2_b_in, qr2_c_in, qr2_d_in;
    wire [31:0] qr3_a_in, qr3_b_in, qr3_c_in, qr3_d_in;
    reg phase;

    // QR0 inputs
    assign qr0_a_in = state[0];
    assign qr0_b_in = phase ? state[5]  : state[4];   
    assign qr0_c_in = phase ? state[10] : state[8];   
    assign qr0_d_in = phase ? state[15] : state[12];  
    
    // QR1 inputs
    assign qr1_a_in = state[1];
    assign qr1_b_in = phase ? state[6]  : state[5];
    assign qr1_c_in = phase ? state[11] : state[9];
    assign qr1_d_in = phase ? state[12] : state[13];
    
    // QR2 inputs
    assign qr2_a_in = state[2];
    assign qr2_b_in = phase ? state[7]  : state[6];
    assign qr2_c_in = phase ? state[8]  : state[10];
    assign qr2_d_in = phase ? state[13] : state[14];
    
    // QR3 inputs
    assign qr3_a_in = state[3];
    assign qr3_b_in = phase ? state[4]  : state[7];
    assign qr3_c_in = phase ? state[9]  : state[11];
    assign qr3_d_in = phase ? state[14] : state[15];

    //quarter round outputs
    wire [31:0] qr0_a, qr0_b, qr0_c, qr0_d;
    wire [31:0] qr1_a, qr1_b, qr1_c, qr1_d;
    wire [31:0] qr2_a, qr2_b, qr2_c, qr2_d;
    wire [31:0] qr3_a, qr3_b, qr3_c, qr3_d;

    //module instantiations
    quarter_round round0(qr0_a_in, qr0_b_in, qr0_c_in, qr0_d_in, qr0_a, qr0_b, qr0_c, qr0_d);
    quarter_round round1(qr1_a_in, qr1_b_in, qr1_c_in, qr1_d_in, qr1_a, qr1_b, qr1_c, qr1_d);
    quarter_round round2(qr2_a_in, qr2_b_in, qr2_c_in, qr2_d_in, qr2_a, qr2_b, qr2_c, qr2_d);
    quarter_round round3(qr3_a_in, qr3_b_in, qr3_c_in, qr3_d_in, qr3_a, qr3_b, qr3_c, qr3_d);

    //FSM
    reg [1:0] state_fsm;

    localparam IDLE = 0x0;
    localparam COL = 0x1;
    localparam DIAGONAL = 0x2;
    localparam DONE = 0x3;

    reg [3:0] counter;

    assign cipher = {state[0], state[1], state[2], state[3],
                    state[4], state[5], state[6], state[7],
                    state[8], state[9], state[10], state[11],
                    state[12], state[13], state[14], state[15]};

    always @ (posedge clk)
        begin
            if (!resetn) begin
                phase <= 0;
                counter <= 0;
                state_fsm <= IDLE;
                ready <= 0;

            end
            else begin  
                case(state_fsm)

                    IDLE: begin
                        ready <= 0;

                        if (enable && !ready) begin
                            state_fsm <= COL;

                            //state matrix initulaizatin
                            //chacha20 constants
                            state[0] <= 32'h61707865;
                            state[1] <= 32'h3320646e;
                            state[2] <= 32'h79622d32;
                            state[3] <= 32'h6b206574;
                            //masterkey
                            state[4] <= 32'hf9d7e836;
                            state[5] <= 32'h5065c10a;
                            state[6] <= 32'h784bde64;
                            state[7] <= 32'ha57b0853;
                            state[8] <= 32'hae7c8013;
                            state[9] <= 32'h1b75c64d;
                            state[10] <= 32'hb42931dd;
                            state[11] <= 32'h9df6b36f;
                            //counter + nonce
                            state[12] <= 0; 
                            state[13] <= nonce[95:64];
                            state[14] <= nonce[63:32];
                            state[15] <= nonce[31:0];
                        end

                    end

                    COL: begin

                        state[0] <= qr0_a; state[4] <= qr0_b; state[8] <= qr0_c; state[12] <= qr0_d;
                        state[1]  <= qr1_a; state[5]  <= qr1_b; state[9]  <= qr1_c; state[13] <= qr1_d;
                        state[2]  <= qr2_a; state[6]  <= qr2_b; state[10] <= qr2_c; state[14] <= qr2_d;
                        state[3]  <= qr3_a; state[7]  <= qr3_b; state[11] <= qr3_c; state[15] <= qr3_d;

                        state_fsm <= DIAGONAL;
                        phase <= 1;
                    end

                    DIAGONAL: begin
                        state[0]  <= qr0_a; state[5]  <= qr0_b; state[10] <= qr0_c; state[15] <= qr0_d;
                        state[1]  <= qr1_a; state[6]  <= qr1_b; state[11] <= qr1_c; state[12] <= qr1_d;
                        state[2]  <= qr2_a; state[7]  <= qr2_b; state[8]  <= qr2_c; state[13] <= qr2_d;
                        state[3]  <= qr3_a; state[4]  <= qr3_b; state[9]  <= qr3_c; state[14] <= qr3_d;

                        counter <= counter + 1;
                        phase <= 0;    

                        if (counter == 9) state_fsm <= DONE;
                        else state_fsm <= COL;
                    end 
                    
                    DONE: begin
                        state_fsm <= IDLE;
                        ready <= 1;
                    end
                endcase
            end 
    
        end

endmodule

