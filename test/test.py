import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

DATASET = [
    # id, pan, expected label
    ("T1",  "4029163778265418", "VALID"),
    ("T2",  "4482107951124058", "VALID"),
    ("T3",  "4500980840795553", "VALID"),
    ("T4",  "4510642735026001", "VALID"),
    ("T5",  "4514551483583699", "VALID"),
    ("T6",  "4536703294718295", "VALID"),
    ("T7",  "4544890363345876", "VALID"),
    ("T8",  "4500980840795554", "INVALID_LUHN"),
    ("T9",  "451064273502",     "INVALID_LENGTH"),   # 12 digits
    ("T10", "4999710862699773", "INVALID_IIN_UNKNOWN"),
]

# Extra: same PAN as T1, different nonce => should produce different token64
EXTRA_REPEAT = ("T1_REPEAT", "4029163778265418", "VALID")

# Helpers: reset / drive inputs
async def reset_dut(dut):
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

async def pulse_start(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

async def pulse_nonce(dut, nonce_int):
    # tb.v must expose nonce_in + nonce_valid
    dut.nonce_in.value = nonce_int
    dut.nonce_valid.value = 1
    await RisingEdge(dut.clk)
    dut.nonce_valid.value = 0

async def send_pan(dut, pan_str):
    assert pan_str.isdigit()
    digits = [int(c) for c in pan_str]

    # Stream digits. Assert pan_end on the last digit.
    for i, d in enumerate(digits):
        dut.digit_in.value = d
        dut.digit_valid.value = 1
        dut.pan_end.value = 1 if (i == len(digits) - 1) else 0

        await RisingEdge(dut.clk)

        dut.digit_valid.value = 0
        dut.pan_end.value = 0
        dut.digit_in.value = 0

        await RisingEdge(dut.clk)

    return digits

async def wait_for_token(dut, max_cycles=600):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.token_valid.value) == 1:
            tok64 = int(dut.token64.value) if hasattr(dut, "token64") else None
            tag16 = int(dut.token_tag16.value) if hasattr(dut, "token_tag16") else None
            return tok64, tag16
    raise AssertionError("token_valid never asserted")

async def assert_no_token(dut, max_cycles=500):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.token_valid.value) == 1:
            raise AssertionError("token_valid asserted unexpectedly")

def expected_behavior(label, length):
    """
    What your CURRENT RTL does:
    - token fires only when (len==16) AND luhn_valid==1
    - meta_valid in your classifier is also gated by luhn_valid (and card_done)
    - meta_hit just indicates whether prefix4 matched the lookup table
    """
    if length != 16:
        return dict(expect_luhn=0, expect_token=False, expect_meta_valid=0, expect_meta_hit=None)

    if label == "VALID":
        return dict(expect_luhn=1, expect_token=True,  expect_meta_valid=1, expect_meta_hit=1)
    if label == "INVALID_LUHN":
        return dict(expect_luhn=0, expect_token=False, expect_meta_valid=0, expect_meta_hit=None)
    if label == "INVALID_IIN_UNKNOWN":
        # Luhn can still be valid, but lookup should miss.
        # Tokenizer currently does NOT care about meta_hit, so token should still appear.
        return dict(expect_luhn=1, expect_token=True,  expect_meta_valid=1, expect_meta_hit=0)

    # fallback
    return dict(expect_luhn=0, expect_token=False, expect_meta_valid=0, expect_meta_hit=None)

# The test
@cocotb.test()
async def run_dataset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # init inputs
    dut.start.value = 0
    dut.pan_end.value = 0
    dut.digit_valid.value = 0
    dut.digit_in.value = 0

    # nonce inputs exist in your tb.v
    dut.nonce_in.value = 0
    dut.nonce_valid.value = 0

    await reset_dut(dut)

    all_tests = DATASET + [EXTRA_REPEAT]

    base_nonce = 0x0123456789ABCDEF01230000  # 96-bit-ish
    last_token_for_pan = {}  # for "same PAN diff nonce => diff token" check

    for idx, (tid, pan, label) in enumerate(all_tests):
        digits = [int(c) for c in pan]
        beh = expected_behavior(label, len(digits))

        dut._log.info(f"\n=== {tid} label={label} pan={pan} ===")

        # different nonce each test
        await pulse_nonce(dut, base_nonce + idx)

        # start new capture
        await pulse_start(dut)

        # stream digits into pan_stream through tb.v
        sent_digits = await send_pan(dut, pan)

        # settle
        await RisingEdge(dut.clk)

        #  pan_stream checks 
        assert int(dut.len_final.value) == len(sent_digits), f"{tid}: len_final mismatch"
        assert int(dut.pan_ready.value) == 1, f"{tid}: pan_ready should be 1"

        # prefix / iin_prefix sanity: first 4 digits should match
        iin = int(dut.iin_prefix.value)
        def nib(i): return (iin >> (4 * i)) & 0xF
        for i in range(min(4, len(sent_digits))):
            assert nib(i) == sent_digits[i], f"{tid}: prefix digit {i} mismatch"

        #  Luhn check (proves luhn module is working) 
        if hasattr(dut, "luhn_valid"):
            got = int(dut.luhn_valid.value)
            assert got == beh["expect_luhn"], f"{tid}: luhn_valid={got} expected={beh['expect_luhn']}"

        #  Metadata check (proves classifier is working) 
        if hasattr(dut, "meta_valid"):
            mv = int(dut.meta_valid.value)
            assert mv == beh["expect_meta_valid"], f"{tid}: meta_valid={mv} expected={beh['expect_meta_valid']}"

            # Only check hit when meta_valid=1 and we have an expectation
            if (beh["expect_meta_hit"] is not None) and (mv == 1):
                mh = int(dut.meta_hit.value)
                assert mh == beh["expect_meta_hit"], f"{tid}: meta_hit={mh} expected={beh['expect_meta_hit']}"

            dut._log.info(
                f"Meta: valid={int(dut.meta_valid.value)} hit={int(dut.meta_hit.value)} "
                f"brand_id={int(dut.brand_id.value)} type_id={int(dut.type_id.value)} issuer_id={int(dut.issuer_id.value)}"
            )

        # Token check (proves pan_tokenizer + chacha20core are working) 
        if hasattr(dut, "token_valid"):
            if beh["expect_token"]:
                tok64, tag16 = await wait_for_token(dut)
                dut._log.info(f"Token: token64=0x{tok64:016x} tag16=0x{tag16:04x}")

                # For the repeat case: same PAN, different nonce => different token
                if pan in last_token_for_pan:
                    prev = last_token_for_pan[pan]
                    assert tok64 != prev, f"{tid}: token64 did not change with different nonce"
                last_token_for_pan[pan] = tok64
            else:
                await assert_no_token(dut)
                dut._log.info("Token: (expected) no token_valid pulse")