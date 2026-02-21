// Luhn Algorithm Validator
// Validates a 16-digit decimal number using the Luhn algorithm
// Input: 16 digits (each 4 bits, BCD encoded)
// Output: valid (1 if checksum passes, 0 otherwise)


module luhn_validator (
    input  logic [3:0] digit [15:0],  // 16 digits, digit[0] is rightmost
    output logic       valid
);

    // Processed digit values after doubling and digit sum
    logic [3:0] processed [15:0];
    
    // Total sum
    logic [6:0] total_sum;
    
    // Process each digit
    // Digits at odd positions from right (digit[1], [3], [5], etc.) are doubled
    // Digits at even positions from right (digit[0], [2], [4], etc.) stay the same
    
    always_comb begin
        // Process digit 0 (rightmost) - no doubling
        processed[0] = digit[0];
        
        // Process digit 1 - double it
        if (digit[1] <= 4'd4) begin
            processed[1] = digit[1] << 1;  // Just double
        end else begin
            processed[1] = (digit[1] << 1) - 4'd9;  // Double and subtract 9 (adds digits)
        end
        
        // Process digit 2 - no doubling
        processed[2] = digit[2];
        
        // Process digit 3 - double it
        if (digit[3] <= 4'd4) begin
            processed[3] = digit[3] << 1;
        end else begin
            processed[3] = (digit[3] << 1) - 4'd9;
        end
        
        // Process digit 4 - no doubling
        processed[4] = digit[4];
        
        // Process digit 5 - double it
        if (digit[5] <= 4'd4) begin
            processed[5] = digit[5] << 1;
        end else begin
            processed[5] = (digit[5] << 1) - 4'd9;
        end
        
        // Process digit 6 - no doubling
        processed[6] = digit[6];
        
        // Process digit 7 - double it
        if (digit[7] <= 4'd4) begin
            processed[7] = digit[7] << 1;
        end else begin
            processed[7] = (digit[7] << 1) - 4'd9;
        end
        
        // Process digit 8 - no doubling
        processed[8] = digit[8];
        
        // Process digit 9 - double it
        if (digit[9] <= 4'd4) begin
            processed[9] = digit[9] << 1;
        end else begin
            processed[9] = (digit[9] << 1) - 4'd9;
        end
        
        // Process digit 10 - no doubling
        processed[10] = digit[10];
        
        // Process digit 11 - double it
        if (digit[11] <= 4'd4) begin
            processed[11] = digit[11] << 1;
        end else begin
            processed[11] = (digit[11] << 1) - 4'd9;
        end
        
        // Process digit 12 - no doubling
        processed[12] = digit[12];
        
        // Process digit 13 - double it
        if (digit[13] <= 4'd4) begin
            processed[13] = digit[13] << 1;
        end else begin
            processed[13] = (digit[13] << 1) - 4'd9;
        end
        
        // Process digit 14 - no doubling
        processed[14] = digit[14];
        
        // Process digit 15 - double it
        if (digit[15] <= 4'd4) begin
            processed[15] = digit[15] << 1;
        end else begin
            processed[15] = (digit[15] << 1) - 4'd9;
        end
        
        // Calculate total sum
        total_sum = processed[0] + processed[1] + processed[2] + processed[3] +
                    processed[4] + processed[5] + processed[6] + processed[7] +
                    processed[8] + processed[9] + processed[10] + processed[11] +
                    processed[12] + processed[13] + processed[14] + processed[15];
        
        // Valid if sum modulo 10 equals 0 (last digit is 0)
        valid = (total_sum % 7'd10) == 7'd0;
    end

endmodule