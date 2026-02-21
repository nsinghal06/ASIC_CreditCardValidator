// Quarter Round Function for ChaCha Cipher
// Performs additions, XORs, and rotations on four 32-bit words

module QRfunction (
    input  logic [31:0] a_in,
    input  logic [31:0] b_in,
    input  logic [31:0] c_in,
    input  logic [31:0] d_in,
    output logic [31:0] a_out,
    output logic [31:0] b_out,
    output logic [31:0] c_out,
    output logic [31:0] d_out
);

    // Internal signals for each step
    logic [31:0] a1, b1, c1, d1;
    logic [31:0] a2, b2, c2, d2;
    logic [31:0] a3, b3, c3, d3;
    
    // Temporary signals for XOR results before rotation
    logic [31:0] d1_xor, b2_xor, d3_xor, b_out_xor;

    // Step 1: a += b; d ^= a; d <<<= 16;
    assign a1 = a_in + b_in;
    assign b1 = b_in;
    assign c1 = c_in;
    assign d1_xor = d_in ^ a1;
    assign d1 = {d1_xor[15:0], d1_xor[31:16]};  // Rotate left by 16

    // Step 2: c += d; b ^= c; b <<<= 12;
    assign c2 = c1 + d1;
    assign a2 = a1;
    assign b2_xor = b1 ^ c2;
    assign b2 = {b2_xor[19:0], b2_xor[31:20]};  // Rotate left by 12
    assign d2 = d1;

    // Step 3: a += b; d ^= a; d <<<= 8;
    assign a3 = a2 + b2;
    assign b3 = b2;
    assign c3 = c2;
    assign d3_xor = d2 ^ a3;
    assign d3 = {d3_xor[23:0], d3_xor[31:24]};  // Rotate left by 8

    // Step 4: c += d; b ^= c; b <<<= 7;
    assign c_out = c3 + d3;
    assign a_out = a3;
    assign b_out_xor = b3 ^ c_out;
    assign b_out = {b_out_xor[24:0], b_out_xor[31:25]};  // Rotate left by 7
    assign d_out = d3;

endmodule
