import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

# TEST MODES
# MODE A: prefix + auto-generate Luhn-valid 16-digit PAN (recommended)
# MODE B: explicit 16-digit PAN string
USE_SYNTHETIC_PREFIX4 = True

EXPLICIT_PAN_STR = "4535000000000000"  # used only when USE_SYNTHETIC_PREFIX4 = False
EXPECT_LUHN_VALID = True               # only used in explicit mode

PREFIX4_STR = "4535"
PAYLOAD_DIGITS = [0] * 11              # 4 + 11 = 15 digits, last digit computed by Luhn

RUN_NEGATIVE_TEST = True               # flip last digit to force Luhn fail


# Helper: compute Luhn check digit for 16-digit PAN
def luhn_check_digit(first15_digits):
    total = 0
    digits = first15_digits + [0]  # placeholder check digit
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


async def pulse_nonce(dut, nonce_int):
    # Requires tb.v to expose nonce_in + nonce_valid
    dut.nonce_in.value = nonce_int
    dut.nonce_valid.value = 1
    await RisingEdge(dut.clk)
    dut.nonce_valid.value = 0


def make_digits():
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


async def wait_for_token_valid(dut, max_cycles=250):
    # Requires tb.v to expose token_valid + token_tag16
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.token_valid.value) == 1:
            return int(dut.token_tag16.value)
    raise AssertionError("token_valid never asserted")


async def assert_token_not_pulsed(dut, max_cycles=250):
    # Ensure token_valid does NOT pulse within window
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.token_valid.value) == 1:
            raise AssertionError("token_valid should NOT assert (unexpected pulse)")


# Test
@cocotb.test()
async def pan_stream_plus_meta_and_token(dut):
    # Start clock
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # Init inputs
    dut.start.value = 0
    dut.pan_end.value = 0
    dut.digit_valid.value = 0
    dut.digit_in.value = 0
    #dut.abort.value = 0

    # If tokenizer signals exist, init them too (safe)
    if hasattr(dut, "nonce_in"):
        dut.nonce_in.value = 0
    if hasattr(dut, "nonce_valid"):
        dut.nonce_valid.value = 0

    await reset_dut(dut)

    #  Set nonce BEFORE sending PAN (token should depend on this) 
    if hasattr(dut, "nonce_in") and hasattr(dut, "nonce_valid"):
        await pulse_nonce(dut, 0x0123456789ABCDEF01234567)

    #  Start capture 
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    #  Send digits
    digits = make_digits()
    for i, d in enumerate(digits):
        await send_digit(dut, d, last=(i == len(digits) - 1))

    # settle cycle
    await RisingEdge(dut.clk)

    #  Basic pan_stream checks 
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

    #  Luhn check behavior 
    if hasattr(dut, "luhn_valid"):
        if USE_SYNTHETIC_PREFIX4:
            assert int(dut.luhn_valid.value) == 1, f"Expected luhn_valid=1, got {int(dut.luhn_valid.value)}"
        else:
            exp = 1 if EXPECT_LUHN_VALID else 0
            assert int(dut.luhn_valid.value) == exp, f"Expected luhn_valid={exp}, got {int(dut.luhn_valid.value)}"

    #Metadata check behavior 
    if hasattr(dut, "meta_valid"):
        if USE_SYNTHETIC_PREFIX4:
            assert int(dut.meta_valid.value) == 1, "Expected meta_valid=1 (synthetic is Luhn-valid)"
            assert int(dut.meta_hit.value) == 1, "Expected meta_hit=1 for known prefix4"
        else:
            if EXPECT_LUHN_VALID:
                assert int(dut.meta_valid.value) == 1, "Expected meta_valid=1 for Luhn-valid explicit PAN"
            else:
                assert int(dut.meta_valid.value) == 0, "Expected meta_valid=0 for Luhn-invalid explicit PAN"

        dut._log.info(
            f"Meta: brand_id={int(dut.brand_id.value)} issuer_id={int(dut.issuer_id.value)} "
            f"type_id={int(dut.type_id.value)} hit={int(dut.meta_hit.value)}"
        )

    #  Token check: only if tokenizer signals exist 
    if hasattr(dut, "token_valid") and hasattr(dut, "token_tag16"):
        # If Luhn valid, token_valid should pulse and produce a tag
        should_have_token = True
        if not USE_SYNTHETIC_PREFIX4 and not EXPECT_LUHN_VALID:
            should_have_token = False

        if should_have_token:
            tag1 = await wait_for_token_valid(dut, max_cycles=300)
            dut._log.info(f"Token tag16 (nonce1) = 0x{tag1:04x}")
        else:
            await assert_token_not_pulsed(dut, max_cycles=200)

    # Negative test: break Luhn
    if RUN_NEGATIVE_TEST:
        # Change nonce too (optional)
        if hasattr(dut, "nonce_in") and hasattr(dut, "nonce_valid"):
            await pulse_nonce(dut, 0x111122223333444455556666)

        # Start new card
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        bad_digits = digits.copy()
        bad_digits[-1] = (bad_digits[-1] + 1) % 10  # flip check digit to force invalid

        for i, d in enumerate(bad_digits):
            await send_digit(dut, d, last=(i == len(bad_digits) - 1))

        await RisingEdge(dut.clk)

        if hasattr(dut, "luhn_valid"):
            assert int(dut.luhn_valid.value) == 0, "Expected luhn_valid=0 for bad PAN"
        if hasattr(dut, "meta_valid"):
            assert int(dut.meta_valid.value) == 0, "Expected meta_valid=0 when Luhn fails"

        # Token should NOT publish when Luhn fails
        if hasattr(dut, "token_valid"):
            await assert_token_not_pulsed(dut, max_cycles=250)