`default_nettype none

module iin_prefix4_classifier (
    input  logic        clk,
    input  logic        rst_n,

    // control
    input  logic        start,       // clears outputs for new card
    input  logic        card_done,    // 1-cycle pulse at end of PAN
    input  logic        luhn_valid,   // from your luhn bridge

    // data
    input  logic [15:0] prefix4_bcd, // iin_prefix[15:0] (4 BCD digits, nibble0=first digit)

    // outputs (IDs)
    output logic [2:0]  brand_id,
    output logic [4:0]  issuer_id,
    output logic [1:0]  type_id,

    // status
    output logic        meta_hit,     // table matched
    output logic        meta_valid    // latched only when card_done && luhn_valid
);

    // ---------- ID encoding ----------
    localparam logic [2:0] BRAND_UNKNOWN = 3'd0;
    localparam logic [2:0] BRAND_VISA    = 3'd1;
    localparam logic [2:0] BRAND_MC      = 3'd2;
    localparam logic [2:0] BRAND_AMEX    = 3'd3;

    localparam logic [1:0] TYPE_UNKNOWN  = 2'd0;
    localparam logic [1:0] TYPE_CREDIT   = 2'd1;
    localparam logic [1:0] TYPE_DEBIT    = 2'd2;
    localparam logic [1:0] TYPE_PREPAID  = 2'd3;

    localparam logic [4:0] ISS_UNKNOWN   = 5'd0;
    localparam logic [4:0] ISS_TD        = 5'd1;
    localparam logic [4:0] ISS_CIBC      = 5'd2;
    localparam logic [4:0] ISS_RBC       = 5'd3;
    localparam logic [4:0] ISS_DESJ      = 5'd4;
    localparam logic [4:0] ISS_SCOTIA    = 5'd5;
    localparam logic [4:0] ISS_LAUR      = 5'd6;

    // digits from BCD (nibble0 is first digit)
    logic [3:0] d0, d1;
    assign d0 = prefix4_bcd[3:0];
    assign d1 = prefix4_bcd[7:4];

    // fallback brand guess from first 1–2 digits
    logic [2:0] brand_fallback;
    always_comb begin
        brand_fallback = BRAND_UNKNOWN;
        if (d0 == 4'd4) brand_fallback = BRAND_VISA;
        else if (d0 == 4'd5) brand_fallback = BRAND_MC;
        else if (d0 == 4'd3 && (d1 == 4'd4 || d1 == 4'd7)) brand_fallback = BRAND_AMEX;
    end

    // combinational classification result (this is the “GPU-ish parallel compare”)
    logic [2:0]  brand_c;
    logic [4:0]  issuer_c;
    logic [1:0]  type_c;
    logic        hit_c;

    always_comb begin
        // defaults (no match)
        hit_c    = 1'b0;
        brand_c  = brand_fallback;
        issuer_c = ISS_UNKNOWN;
        type_c   = TYPE_UNKNOWN;

        // NOTE: these constants match your BCD packing:
        // key "4510" => nibble0=4 nibble1=5 nibble2=1 nibble3=0 => 16'h0154
        unique case (prefix4_bcd)

            // TD
            16'h9204: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_TD;   type_c=TYPE_DEBIT;  end // 4029
            16'h2844: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_TD;   type_c=TYPE_CREDIT; end // 4482
            16'h0254: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_TD;   type_c=TYPE_CREDIT; end // 4520

            // CIBC
            16'h0054: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_CIBC; type_c=TYPE_CREDIT; end // 4500
            16'h2054: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_CIBC; type_c=TYPE_CREDIT; end // 4502
            16'h3054: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_CIBC; type_c=TYPE_CREDIT; end // 4503
            16'h4054: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_CIBC; type_c=TYPE_CREDIT; end // 4504
            16'h5054: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_CIBC; type_c=TYPE_CREDIT; end // 4505

            // RBC
            16'h0154: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_RBC;  type_c=TYPE_CREDIT; end // 4510
            16'h2154: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_RBC;  type_c=TYPE_CREDIT; end // 4512
            16'h4154: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_RBC;  type_c=TYPE_CREDIT; end // 4514
            16'h6154: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_RBC;  type_c=TYPE_CREDIT; end // 4516
            16'h9154: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_RBC;  type_c=TYPE_DEBIT;  end // 4519

            // Desjardins
            16'h0354: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_DESJ; type_c=TYPE_CREDIT; end // 4530
            16'h0454: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_DESJ; type_c=TYPE_CREDIT; end // 4540

            // Scotiabank
            16'h5354: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_SCOTIA; type_c=TYPE_CREDIT; end // 4535
            16'h6354: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_SCOTIA; type_c=TYPE_DEBIT;  end // 4536
            16'h7354: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_SCOTIA; type_c=TYPE_CREDIT; end // 4537
            16'h8354: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_SCOTIA; type_c=TYPE_CREDIT; end // 4538

            // Laurentian
            16'h4454: begin hit_c=1'b1; brand_c=BRAND_VISA; issuer_c=ISS_LAUR; type_c=TYPE_CREDIT; end // 4544

            default: begin end
        endcase
    end

    // latch outputs only when card is done AND Luhn passed
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            brand_id   <= BRAND_UNKNOWN;
            issuer_id  <= ISS_UNKNOWN;
            type_id    <= TYPE_UNKNOWN;
            meta_hit   <= 1'b0;
            meta_valid <= 1'b0;
        end else begin
            if (start) begin
                meta_valid <= 1'b0;
                meta_hit   <= 1'b0;
                brand_id   <= BRAND_UNKNOWN;
                issuer_id  <= ISS_UNKNOWN;
                type_id    <= TYPE_UNKNOWN;
            end

            if (card_done) begin
                if (luhn_valid) begin
                    brand_id   <= brand_c;
                    issuer_id  <= issuer_c;
                    type_id    <= type_c;
                    meta_hit   <= hit_c;
                    meta_valid <= 1'b1;
                end else begin
                    // if invalid PAN, don't publish metadata
                    meta_valid <= 1'b0;
                    meta_hit   <= 1'b0;
                    brand_id   <= BRAND_UNKNOWN;
                    issuer_id  <= ISS_UNKNOWN;
                    type_id    <= TYPE_UNKNOWN;
                end
            end
        end
    end

endmodule

`default_nettype wire