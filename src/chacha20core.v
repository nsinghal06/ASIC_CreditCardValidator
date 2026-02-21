module chacha20core(resetn, clk, nonce, cipher, done)

    input [95:0] nonce; 
    input clk, resetn, enable;
    output logic [511:0] cipher; 
    output done;

    logic [31:0] state [0:15]; //state matrix

    //cha cha 20 fixed constants
    assign state[0] = 0x61707865;
    assign state[1] = 0x3320646e;
    assign state[2] = 0x79622d32;
    assign state[3] = 0x6b206574;

    //masterkey
    assign state[4] = 0xf9d7e836;
    assign state[5] = 0x5065c10a;
    assign state[6] = 0x784bde64;
    assign state[7] = 0xa57b0853;
    assign state[8] = 0xae7c8013;
    assign state[9] = 0x1b75c64d;
    assign state[10] = 0xb42931dd;
    assign state[11] = 0x9df6b36f;

    //counter + nonce
    assign state[12] = 0; 
    assign state[13] = nonce[95:64];
    assign state[14] = nonce[63:32];
    assign state[15] = nonce[31:0];

    //quarter round inputs
    wire [31:0] qr0_a_in, qr0_b_in, qr0_c_in, qr0_d_in;
    wire [31:0] qr1_a_in, qr1_b_in, qr1_c_in, qr1_d_in;
    wire [31:0] qr2_a_in, qr2_b_in, qr2_c_in, qr2_d_in;
    wire [31:0] qr3_a_in, qr3_b_in, qr3_c_in, qr3_d_in;
    reg phase;

    // QR0 inputs
    assign qr0_a_in = s[0];
    assign qr0_b_in = phase ? s[5]  : s[4];   
    assign qr0_c_in = phase ? s[10] : s[8];   
    assign qr0_d_in = phase ? s[15] : s[12];  
    
    // QR1 inputs
    assign qr1_a_in = s[1];
    assign qr1_b_in = phase ? s[6]  : s[5];
    assign qr1_c_in = phase ? s[11] : s[9];
    assign qr1_d_in = phase ? s[12] : s[13];
    
    // QR2 inputs
    assign qr2_a_in = s[2];
    assign qr2_b_in = phase ? s[7]  : s[6];
    assign qr2_c_in = phase ? s[8]  : s[10];
    assign qr2_d_in = phase ? s[13] : s[14];
    
    // QR3 inputs
    assign qr3_a_in = s[3];
    assign qr3_b_in = phase ? s[4]  : s[7];
    assign qr3_c_in = phase ? s[9]  : s[11];
    assign qr3_d_in = phase ? s[14] : s[15];

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
    reg [1:0] state;

    localparam ITERATE = 0x0;
    localparam COL = 0x1;
    localparam DIAGONAL = 0x2;
    localparam DONE = 0x3;

    reg [3:0] counter;

    assign cipher = {s[0], s[1], s[2], s[3],
                    s[4], s[5], s[6], s[7],
                    s[8], s[9], s[10], s[11],
                    s[12], s[13], s[14], s[15]};

    always @ (posedge clk)
        begin
            if (resetn || state == IDLE) 
                phase <= 0;
                counter <= 0;
                state <= IDLE;

            else if (enable) state <= COL;
        
            else if (state == COL) begin

                s[0] <= qr0_a; s[4] <= qr0_b; s[8] <= qr0_c; s[12] <= qr0_d;
                s[1]  <= qr1_a; s[5]  <= qr1_b; s[9]  <= qr1_c; s[13] <= qr1_d;
                s[2]  <= qr2_a; s[6]  <= qr2_b; s[10] <= qr2_c; s[14] <= qr2_d;
                s[3]  <= qr3_a; s[7]  <= qr3_b; s[11] <= qr3_c; s[15] <= qr3_d;

                state <= DIAGONAL;
                phase <= 1;
            end

            else if (state == DIAGONAL) begin

                s[0]  <= qr0_a; s[5]  <= qr0_b; s[10] <= qr0_c; s[15] <= qr0_d;
                s[1]  <= qr1_a; s[6]  <= qr1_b; s[11] <= qr1_c; s[12] <= qr1_d;
                s[2]  <= qr2_a; s[7]  <= qr2_b; s[8]  <= qr2_c; s[13] <= qr2_d;
                s[3]  <= qr3_a; s[4]  <= qr3_b; s[9]  <= qr3_c; s[14] <= qr3_d;

                counter <= counter + 1;
                phase <= 0;    

                if (counter == 9) state <= DONE;
                else state <= COL;
            end 

            else if (state == DONE) begin
                state <= IDLE;
                done <= 1;
            end
    
        end

endmodule