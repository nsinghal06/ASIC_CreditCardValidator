import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock


BRAND_STR = {0:"UNKNOWN", 1:"VISA", 2:"MASTERCARD", 3:"AMEX"}
TYPE_STR  = {0:"UNKNOWN", 1:"CREDIT", 2:"DEBIT", 3:"PREPAID"}
ISSUER_STR= {0:"UNKNOWN", 1:"TD", 2:"CIBC", 3:"RBC", 4:"DESJ", 5:"SCOTIA", 6:"LAUR"}

DATASET = [
    ("T1",  "4029163778265418", "VALID"),
    ("T2",  "4482107951124058", "VALID"),
    ("T3",  "4500980840795553", "VALID"),
    ("T4",  "4510642735026001", "VALID"),
    ("T5",  "4514551483583699", "VALID"),
    ("T6",  "4536703294718295", "VALID"),
    ("T7",  "4544890363345876", "VALID"),
    ("T8",  "4500980840795554", "INVALID_LUHN"),
    ("T9",  "451064273502",     "INVALID_LENGTH"),
    ("T10", "4999710862699773", "INVALID_IIN_UNKNOWN"),
]

EXTRA_REPEAT = ("T1_REPEAT", "4029163778265418", "VALID")

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
    dut.nonce_in.value = nonce_int
    dut.nonce_valid.value = 1
    await RisingEdge(dut.clk)
    dut.nonce_valid.value = 0

async def send_pan(dut, pan_str):
    assert pan_str.isdigit()
    digits = [int(c) for c in pan_str]
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
    if length != 16:
        return dict(expect_luhn=0, expect_token=False, expect_meta_valid=0, expect_meta_hit=None)
    if label == "VALID":
        return dict(expect_luhn=1, expect_token=True,  expect_meta_valid=1, expect_meta_hit=1)
    if label == "INVALID_LUHN":
        return dict(expect_luhn=0, expect_token=False, expect_meta_valid=0, expect_meta_hit=None)
    if label == "INVALID_IIN_UNKNOWN":
        return dict(expect_luhn=1, expect_token=True,  expect_meta_valid=1, expect_meta_hit=0)
    return dict(expect_luhn=0, expect_token=False, expect_meta_valid=0, expect_meta_hit=None)

@cocotb.test()
async def run_dataset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.start.value = 0
    dut.pan_end.value = 0
    dut.digit_valid.value = 0
    dut.digit_in.value = 0
    dut.nonce_in.value = 0
    dut.nonce_valid.value = 0

    await reset_dut(dut)

    print(r"""
   _____ _               _____ _             _____ _     _       
  / ____| |             / ____| |           / ____| |   (_)      
 | |    | |__   __     | |    | |__   __   | |    | |__  _ _ __  
 | |    | '_ \ /_ \    | |    | '_ \ / _\  | |    | '_ \| | '_ \ 
 | |____| | | | _  |   | |____| | | | _ |  | |____| | | | | |_) |
  \_____|_| |_|\__|\    \_____|_| |_|\__|\  \_____|_| |_|_| .__/ 
                                                      | |    
                                                      |_|    
                    Credit Card Validator
    """)

    print(" PAN                | Luhn     | BRAND        | TYPE      | ISSUER      | TOKEN64")
    print("--------------------------------------------------------------------------------------")

    all_tests = DATASET + [EXTRA_REPEAT]
    base_nonce = 0x0123456789ABCDEF01230000
    last_token_for_pan = {}

    for idx, (tid, pan, label) in enumerate(all_tests):
        digits = [int(c) for c in pan]
        beh = expected_behavior(label, len(digits))

        await pulse_nonce(dut, base_nonce + idx)
        await pulse_start(dut)
        sent_digits = await send_pan(dut, pan)
        await RisingEdge(dut.clk)

        assert int(dut.len_final.value) == len(sent_digits), f"{tid}: len_final mismatch"
        assert int(dut.pan_ready.value) == 1, f"{tid}: pan_ready should be 1"

        iin = int(dut.iin_prefix.value)
        def nib(i): return (iin >> (4 * i)) & 0xF
        for i in range(min(4, len(sent_digits))):
            assert nib(i) == sent_digits[i], f"{tid}: prefix digit {i} mismatch"

        got_luhn = int(dut.luhn_valid.value)
        assert got_luhn == beh["expect_luhn"], f"{tid}: luhn_valid: {got_luhn} expected: {beh['expect_luhn']}"

        mv = int(dut.meta_valid.value)
        mh = int(dut.meta_hit.value)
        b = int(dut.brand_id.value)
        t = int(dut.type_id.value)
        iss = int(dut.issuer_id.value)

        assert mv == beh["expect_meta_valid"], f"{tid}: meta_valid: {mv} expected: {beh['expect_meta_valid']}"
        if (beh["expect_meta_hit"] is not None) and (mv == 1):
            assert mh == beh["expect_meta_hit"], f"{tid}: meta_hit: {mh} expected: {beh['expect_meta_hit']}"

        status = "VALID" if got_luhn else "INVALID"

        token_field = "-"
        if beh["expect_token"]:
            tok64, tag16 = await wait_for_token(dut)
            token_field = f"0x{tok64:016x}"
            if pan in last_token_for_pan:
                prev = last_token_for_pan[pan]
                assert tok64 != prev, f"{tid}: token64 did not change with different nonce"
            last_token_for_pan[pan] = tok64
        else:
            await assert_no_token(dut)

        print(f"{pan:<19} | {status:<7} | {BRAND_STR.get(b,'?'):<11} | {TYPE_STR.get(t,'?'):<8} | {ISSUER_STR.get(iss,'?'):<10} | {token_field}")