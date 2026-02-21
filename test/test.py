import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

#TEST MODES
# MODE A: prefix (e.g., 4535) + auto-generate a Luhn-valid 16-digit PAN TRUE
# MODE B: explicit 16-digit PAN string (must be 16 digits) FALSE
USE_SYNTHETIC_PREFIX4 = True
EXPLICIT_PAN_STR = "4535000000000000"  #replace this for Mode B 

# For explicit mode: set what you expect
EXPECT_LUHN_VALID = True  # set False if you intentionally use an invalid PAN
PREFIX4_STR = "4535" 
PAYLOAD_DIGITS = [0] * 11  # 11 filler digits (makes 15 total with the 4-digit prefix)

# Optional: run a negative test by flipping the last digit to break Luhn
RUN_NEGATIVE_TEST = True

# Helper: compute Luhn check digit for a 16-digit PAN
def luhn_check_digit(first15_digits):
    """
    first15_digits: list of 15 ints (0..9), left-to-right
    returns: check digit (0..9) to make the 16-digit PAN Luhn-valid
    """
    total = 0
    digits = first15_digits + [0]  # placeholder check digit = 0
    for pos, d in enumerate(reversed(digits)):  # pos=0 is rightmost (check digit)
        if pos % 2 == 1:
            x = d * 2
            if x > 9:
                x -= 9
            total += x
        else:
            total += d
    return (10 - (total % 10)) % 10


# Cocotb helpers
async def reset_dut(dut):
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def send_digit(dut, d, last=False):
    dut.digit_in.value = d
    dut.digit_valid.value = 1
    dut.pan_end.value = 1 if last else 0
    await RisingEdge(dut.clk)
    dut.digit_valid.value = 0
    dut.pan_end.value = 0
    dut.digit_in.value = 0
    await RisingEdge(dut.clk)


def make_digits():
    """
    Returns a 16-digit list of ints (0..9).
    Mode A: prefix4 + payload + computed Luhn check digit
    Mode B: explicit 16-digit PAN string
    """
    if USE_SYNTHETIC_PREFIX4:
        assert len(PREFIX4_STR) == 4 and PREFIX4_STR.isdigit()
        prefix = [int(c) for c in PREFIX4_STR]
        assert len(PAYLOAD_DIGITS) == 11
        first15 = prefix + PAYLOAD_DIGITS
        check = luhn_check_digit(first15)
        return first15 + [check]
    else:
        assert len(EXPLICIT_PAN_STR) == 16 and EXPLICIT_PAN_STR.isdigit()
        return [int(c) for c in EXPLICIT_PAN_STR]


@cocotb.test()
async def pan_stream_plus_meta(dut):
    # Start clock
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # Init inputs
    dut.start.value = 0
    dut.pan_end.value = 0
    dut.digit_valid.value = 0
    dut.digit_in.value = 0
    dut.abort.value = 0

    await reset_dut(dut)

    # Start capture
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Build and send digits
    digits = make_digits()
    for i, d in enumerate(digits):
        await send_digit(dut, d, last=(i == len(digits) - 1))

    # Wait a cycle for outputs to settle
    await RisingEdge(dut.clk)

    # Basic pan_stream checks
    assert int(dut.len_final.value) == 16, f"len_final={int(dut.len_final.value)}"
    assert int(dut.length_ok.value) == 1, "length_ok should be 1"
    assert int(dut.digit_ok.value) == 1, "digit_ok should be 1"
    assert int(dut.error_flag.value) == 0, "error_flag should be 0"
    assert int(dut.pan_ready.value) == 1, "pan_ready should be 1"

    # IIN prefix nibble packing check (first 6 digits)
    iin = int(dut.iin_prefix.value)
    def nib(i): return (iin >> (4 * i)) & 0xF
    for i in range(6):
        assert nib(i) == digits[i], f"IIN digit {i} mismatch: got {nib(i)} expected {digits[i]}"

    # If luhn_valid exists in your tb.v, check it should be 1 for the main test
        # If luhn_valid exists in your tb.v, check expected behavior
    if hasattr(dut, "luhn_valid"):
        if USE_SYNTHETIC_PREFIX4:
            assert int(dut.luhn_valid.value) == 1, f"Expected luhn_valid=1, got {int(dut.luhn_valid.value)}"
        else:
            exp = 1 if EXPECT_LUHN_VALID else 0
            assert int(dut.luhn_valid.value) == exp, f"Expected luhn_valid={exp}, got {int(dut.luhn_valid.value)}"

    # If metadata classifier exists in your tb.v, check meta_valid/hit
    if hasattr(dut, "meta_valid"):
        if USE_SYNTHETIC_PREFIX4:
            assert int(dut.meta_valid.value) == 1, "Expected meta_valid=1 (synthetic is Luhn-valid)"
            assert int(dut.meta_hit.value) == 1, "Expected meta_hit=1 for known prefix4"
        else:
            if EXPECT_LUHN_VALID:
                assert int(dut.meta_valid.value) == 1, "Expected meta_valid=1 for Luhn-valid explicit PAN"
            else:
                assert int(dut.meta_valid.value) == 0, "Expected meta_valid=0 for Luhn-invalid explicit PAN"

        # Optional: print IDs in the log (helps demo)
        dut._log.info(
            f"Meta: brand_id={int(dut.brand_id.value)} issuer_id={int(dut.issuer_id.value)} "
            f"type_id={int(dut.type_id.value)} hit={int(dut.meta_hit.value)}"
        )

    # Negative test: break Luhn and ensure metadata does NOT publish
    if RUN_NEGATIVE_TEST:
        # Start new card
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        bad_digits = digits.copy()
        bad_digits[-1] = (bad_digits[-1] + 1) % 10  # flip check digit to make it invalid

        for i, d in enumerate(bad_digits):
            await send_digit(dut, d, last=(i == len(bad_digits) - 1))

        await RisingEdge(dut.clk)

        if hasattr(dut, "luhn_valid"):
            assert int(dut.luhn_valid.value) == 0, "Expected luhn_valid=0 for bad PAN"

        if hasattr(dut, "meta_valid"):
            assert int(dut.meta_valid.value) == 0, "Expected meta_valid=0 when Luhn fails"