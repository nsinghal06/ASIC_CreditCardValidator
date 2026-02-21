`default_nettype none

module iin_prefix4_classifier (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start,
    input  logic        card_done,
    input  logic        luhn_valid,

    input  logic [15:0] prefix4_bcd,   // iin_prefix[15:0], BCD nibble0=first digit

    output logic [2:0]  brand_id,
    output logic [4:0]  issuer_id,
    output logic [1:0]  type_id,

    output logic        meta_hit,
    output logic        meta_valid
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

    //fallback brand from first digit(s) 
    logic [3:0] d0, d1;
    logic [2:0] brand_fallback;

    assign d0 = prefix4_bcd[3:0];
    assign d1 = prefix4_bcd[7:4];

    always @* begin
        brand_fallback = BRAND_UNKNOWN;
        if (d0 == 4'd4) brand_fallback = BRAND_VISA;
        else if (d0 == 4'd5) brand_fallback = BRAND_MC;
        else if (d0 == 4'd3 && (d1 == 4'd4 || d1 == 4'd7)) brand_fallback = BRAND_AMEX;
    end

    //GPU: parallel hit vector 
    logic [19:0] hit;

    // constants use your BCD packing:
    // "4510" -> 16'h0154 (nibble0=4 nibble1=5 nibble2=1 nibble3=0)
    always @* begin
        hit[0]  = (prefix4_bcd == 16'h9204); // 4029 TD debit
        hit[1]  = (prefix4_bcd == 16'h2844); // 4482 TD credit
        hit[2]  = (prefix4_bcd == 16'h0054); // 4500 CIBC credit
        hit[3]  = (prefix4_bcd == 16'h2054); // 4502 CIBC credit
        hit[4]  = (prefix4_bcd == 16'h3054); // 4503 CIBC credit
        hit[5]  = (prefix4_bcd == 16'h4054); // 4504 CIBC credit
        hit[6]  = (prefix4_bcd == 16'h5054); // 4505 CIBC credit
        hit[7]  = (prefix4_bcd == 16'h0154); // 4510 RBC credit
        hit[8]  = (prefix4_bcd == 16'h2154); // 4512 RBC credit
        hit[9]  = (prefix4_bcd == 16'h4154); // 4514 RBC credit
        hit[10] = (prefix4_bcd == 16'h6154); // 4516 RBC credit
        hit[11] = (prefix4_bcd == 16'h9154); // 4519 RBC debit
        hit[12] = (prefix4_bcd == 16'h0254); // 4520 TD credit
        hit[13] = (prefix4_bcd == 16'h0354); // 4530 Desj credit
        hit[14] = (prefix4_bcd == 16'h5354); // 4535 Scotia credit
        hit[15] = (prefix4_bcd == 16'h6354); // 4536 Scotia debit
        hit[16] = (prefix4_bcd == 16'h7354); // 4537 Scotia credit
        hit[17] = (prefix4_bcd == 16'h8354); // 4538 Scotia credit
        hit[18] = (prefix4_bcd == 16'h0454); // 4540 Desj credit
        hit[19] = (prefix4_bcd == 16'h4454); // 4544 Laurentian credit
    end

    // reduction #1: OR-reduce "did any lane hit?"
    logic hit_any;
    assign hit_any = |hit;

    // reduction #2: priority select metadata (no break; if/else chain)
    logic [2:0] brand_c;
    logic [4:0] issuer_c;
    logic [1:0] type_c;

    always @* begin
        brand_c  = brand_fallback;
        issuer_c = ISS_UNKNOWN;
        type_c   = TYPE_UNKNOWN;

        if      (hit[0])  begin brand_c=BRAND_VISA; issuer_c=ISS_TD;     type_c=TYPE_DEBIT;  end
        else if (hit[1])  begin brand_c=BRAND_VISA; issuer_c=ISS_TD;     type_c=TYPE_CREDIT; end
        else if (hit[2])  begin brand_c=BRAND_VISA; issuer_c=ISS_CIBC;   type_c=TYPE_CREDIT; end
        else if (hit[3])  begin brand_c=BRAND_VISA; issuer_c=ISS_CIBC;   type_c=TYPE_CREDIT; end
        else if (hit[4])  begin brand_c=BRAND_VISA; issuer_c=ISS_CIBC;   type_c=TYPE_CREDIT; end
        else if (hit[5])  begin brand_c=BRAND_VISA; issuer_c=ISS_CIBC;   type_c=TYPE_CREDIT; end
        else if (hit[6])  begin brand_c=BRAND_VISA; issuer_c=ISS_CIBC;   type_c=TYPE_CREDIT; end
        else if (hit[7])  begin brand_c=BRAND_VISA; issuer_c=ISS_RBC;    type_c=TYPE_CREDIT; end
        else if (hit[8])  begin brand_c=BRAND_VISA; issuer_c=ISS_RBC;    type_c=TYPE_CREDIT; end
        else if (hit[9])  begin brand_c=BRAND_VISA; issuer_c=ISS_RBC;    type_c=TYPE_CREDIT; end
        else if (hit[10]) begin brand_c=BRAND_VISA; issuer_c=ISS_RBC;    type_c=TYPE_CREDIT; end
        else if (hit[11]) begin brand_c=BRAND_VISA; issuer_c=ISS_RBC;    type_c=TYPE_DEBIT;  end
        else if (hit[12]) begin brand_c=BRAND_VISA; issuer_c=ISS_TD;     type_c=TYPE_CREDIT; end
        else if (hit[13]) begin brand_c=BRAND_VISA; issuer_c=ISS_DESJ;   type_c=TYPE_CREDIT; end
        else if (hit[14]) begin brand_c=BRAND_VISA; issuer_c=ISS_SCOTIA; type_c=TYPE_CREDIT; end
        else if (hit[15]) begin brand_c=BRAND_VISA; issuer_c=ISS_SCOTIA; type_c=TYPE_DEBIT;  end
        else if (hit[16]) begin brand_c=BRAND_VISA; issuer_c=ISS_SCOTIA; type_c=TYPE_CREDIT; end
        else if (hit[17]) begin brand_c=BRAND_VISA; issuer_c=ISS_SCOTIA; type_c=TYPE_CREDIT; end
        else if (hit[18]) begin brand_c=BRAND_VISA; issuer_c=ISS_DESJ;   type_c=TYPE_CREDIT; end
        else if (hit[19]) begin brand_c=BRAND_VISA; issuer_c=ISS_LAUR;   type_c=TYPE_CREDIT; end
    end

    // latch only when card_done && luhn_valid
    always @(posedge clk or negedge rst_n) begin
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
                    meta_hit   <= hit_any;
                    meta_valid <= 1'b1;
                end else begin
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