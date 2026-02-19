// Testbench for Luhn Algorithm Validator
// Tests the luhn_validator module with sample valid and invalid numbers

module tb_luhn_validator;

    // Signals for DUT
    logic [3:0] digit [15:0];
    logic valid;
    
    // Instantiate the DUT (Device Under Test)
    luhn_validator dut (
        .digit(digit),
        .valid(valid)
    );
    
    // Test stimulus
    initial begin
        $display("TEST START");
        $display("========================================");
        $display("Luhn Algorithm Validator Testbench");
        $display("========================================");
        
        // Test 1: Valid number - 0000000000000018
        // Manual verification: 8 + (1*2) + 0... = 8 + 2 = 10, which is divisible by 10
        $display("\nTest 1: Testing VALID number: 0000-0000-0000-0018");
        digit[0] = 4'd8;  // Rightmost digit
        digit[1] = 4'd1;
        digit[2] = 4'd0;
        digit[3] = 4'd0;
        digit[4] = 4'd0;
        digit[5] = 4'd0;
        digit[6] = 4'd0;
        digit[7] = 4'd0;
        digit[8] = 4'd0;
        digit[9] = 4'd0;
        digit[10] = 4'd0;
        digit[11] = 4'd0;
        digit[12] = 4'd0;
        digit[13] = 4'd0;
        digit[14] = 4'd0;
        digit[15] = 4'd0;  // Leftmost digit
        
        #10;  // Wait for combinational logic to settle
        
        $display("  Input: 0000-0000-0000-0018");
        $display("  Expected: valid = 1");
        $display("  Actual:   valid = %0d", valid);
        
        if (valid === 1'b1) begin
            $display("  ✓ Test 1 PASSED");
        end else begin
            $display("LOG: %0t : ERROR : tb_luhn_validator : dut.valid : expected_value: 1 actual_value: %0d", $time, valid);
            $display("  ✗ Test 1 FAILED");
            $display("ERROR");
            $fatal(1, "Test 1 failed - Valid number incorrectly marked as invalid");
        end
        
        // Test 2: Invalid number - 0000000000000019
        // Manual verification: 9 + (1*2) + 0... = 9 + 2 = 11, NOT divisible by 10
        $display("\nTest 2: Testing INVALID number: 0000-0000-0000-0019");
        digit[0] = 4'd9;  // Changed last digit to make it invalid
        digit[1] = 4'd1;
        digit[2] = 4'd0;
        digit[3] = 4'd0;
        digit[4] = 4'd0;
        digit[5] = 4'd0;
        digit[6] = 4'd0;
        digit[7] = 4'd0;
        digit[8] = 4'd0;
        digit[9] = 4'd0;
        digit[10] = 4'd0;
        digit[11] = 4'd0;
        digit[12] = 4'd0;
        digit[13] = 4'd0;
        digit[14] = 4'd0;
        digit[15] = 4'd0;
        
        #10;  // Wait for combinational logic to settle
        
        $display("  Input: 0000-0000-0000-0019");
        $display("  Expected: valid = 0");
        $display("  Actual:   valid = %0d", valid);
        
        if (valid === 1'b0) begin
            $display("  ✓ Test 2 PASSED");
        end else begin
            $display("LOG: %0t : ERROR : tb_luhn_validator : dut.valid : expected_value: 0 actual_value: %0d", $time, valid);
            $display("  ✗ Test 2 FAILED");
            $display("ERROR");
            $fatal(1, "Test 2 failed - Invalid number incorrectly marked as valid");
        end
        
        // Test 3: Another valid number - 0000000000000026
        // Manual verification: 6 + (2*2) + 0... = 6 + 4 = 10, divisible by 10
        $display("\nTest 3: Testing VALID number: 0000-0000-0000-0026");
        digit[0] = 4'd6;
        digit[1] = 4'd2;
        digit[2] = 4'd0;
        digit[3] = 4'd0;
        digit[4] = 4'd0;
        digit[5] = 4'd0;
        digit[6] = 4'd0;
        digit[7] = 4'd0;
        digit[8] = 4'd0;
        digit[9] = 4'd0;
        digit[10] = 4'd0;
        digit[11] = 4'd0;
        digit[12] = 4'd0;
        digit[13] = 4'd0;
        digit[14] = 4'd0;
        digit[15] = 4'd0;
        
        #10;
        
        $display("  Input: 0000-0000-0000-0026");
        $display("  Expected: valid = 1");
        $display("  Actual:   valid = %0d", valid);
        
        if (valid === 1'b1) begin
            $display("  ✓ Test 3 PASSED");
        end else begin
            $display("LOG: %0t : ERROR : tb_luhn_validator : dut.valid : expected_value: 1 actual_value: %0d", $time, valid);
            $display("  ✗ Test 3 FAILED");
            $display("ERROR");
            $fatal(1, "Test 3 failed - Valid number incorrectly marked as invalid");
        end
        
        // All tests passed
        $display("\n========================================");
        $display("TEST PASSED");
        $display("All 3 tests completed successfully!");
        $display("========================================");
        
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule
