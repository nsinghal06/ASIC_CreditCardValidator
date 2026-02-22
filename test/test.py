import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

BRAND_STR = {0:"UNKNOWN", 1:"VISA", 2:"MASTERCARD", 3:"AMEX"}
TYPE_STR  = {0:"UNKNOWN", 1:"CREDIT", 2:"DEBIT", 3:"PREPAID"}
ISSUER_STR= {0:"UNKNOWN", 1:"TD", 2:"CIBC", 3:"RBC", 4:"DESJ", 5:"SCOTIA", 6:"LAUR"}

"""
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
"""
DATASET = [
    ("T1",  "4029163778265418", "VALID"),
]

EXTRA_REPEAT = ("T1_REPEAT", "4029163778265418", "VALID")

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

def ui_word(digit, digit_valid, start, pan_end):
    return ((digit & 0xF) |
            ((1 if digit_valid else 0) << 4) |
            ((1 if start else 0) << 5) |
            ((1 if pan_end else 0) << 6))

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    # Hold reset for several cycles to ensure all flops clear
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    # Wait a few cycles after reset before starting stimulus
    for _ in range(5):
        await RisingEdge(dut.clk)



async def pulse_start_tt(dut):
    dut.ui_in.value = ui_word(0, 0, 1, 0)
    await RisingEdge(dut.clk)
    dut.ui_in.value = 0
    await RisingEdge(dut.clk)

async def send_pan_tt(dut, pan_str):
    assert pan_str.isdigit()
    digits = [int(c) for c in pan_str]
    for i, d in enumerate(digits):
        last = (i == len(digits) - 1)
        dut.ui_in.value = ui_word(d, 1, 0, 1 if last else 0)
        await RisingEdge(dut.clk)
        dut.ui_in.value = 0
        await RisingEdge(dut.clk)
    return digits

async def wait_for_token64_stream(dut, max_cycles=2000):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        stream_active = (int(dut.uio_out.value) >> 3) & 0x1
        if stream_active == 1:
            break
    else:
        raise AssertionError("token stream never started (uio_out[3] never went high)")

    bytes_out = [0] * 8
    seen = [False] * 8

    for _ in range(max_cycles):
        stream_active = (int(dut.uio_out.value) >> 3) & 0x1
        if stream_active == 0:
            break
        idx = int(dut.uio_out.value) & 0x7
        b = int(dut.uo_out.value) & 0xFF
        if 0 <= idx <= 7:
            bytes_out[idx] = b
            seen[idx] = True
        await RisingEdge(dut.clk)

    if not all(seen):
        raise AssertionError(f"token stream incomplete, missing byte indices: {[i for i,v in enumerate(seen) if not v]}")

    tok64 = 0
    for i in range(7, -1, -1):
        tok64 = (tok64 << 8) | (bytes_out[i] & 0xFF)
    return tok64

async def assert_no_token_stream(dut, max_cycles=1200):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        stream_active = (int(dut.uio_out.value) >> 3) & 0x1
        if stream_active == 1:
            raise AssertionError("token stream started unexpectedly (uio_out[3] went high)")

@cocotb.test()
async def run_dataset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    for _ in range(5):
        await RisingEdge(dut.clk)

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
    last_token_for_pan = {}

    for idx, (tid, pan, label) in enumerate(all_tests):
        digits = [int(c) for c in pan]
        beh = expected_behavior(label, len(digits))

        await pulse_start_tt(dut)
        sent_digits = await send_pan_tt(dut, pan)
        await RisingEdge(dut.clk)

        #debug
       # Wait until uio_out is resolvable (all bits 0/1) or timeout
        for _ in range(10):
            if dut.uio_out.value.is_resolvable:
                break
        else:
            raise AssertionError("uio_out still contains X after timeout")

        # Safely get binary string (may contain 'x' or 'z')
        uio_bits = dut.uio_out.value.binstr
        dut._log.info(f"uio_out binary: {uio_bits}")

        # Extract bits manually from the binary string (LSB is rightmost)
        got_luhn = int(uio_bits[-5])   # bit4 (luhn_valid)
        mv = int(uio_bits[-7])         # bit6 (meta_valid)
        mh = int(uio_bits[-6])         # bit5 (meta_hit)

        b = int(dut.brand_id.value) if hasattr(dut, "brand_id") else 0
        t = int(dut.type_id.value) if hasattr(dut, "type_id") else 0
        iss = int(dut.issuer_id.value) if hasattr(dut, "issuer_id") else 0

        assert got_luhn == beh["expect_luhn"], f"{tid}: luhn_valid: {got_luhn} expected: {beh['expect_luhn']}"
        assert mv == beh["expect_meta_valid"], f"{tid}: meta_valid: {mv} expected: {beh['expect_meta_valid']}"
        if (beh["expect_meta_hit"] is not None) and (mv == 1):
            assert mh == beh["expect_meta_hit"], f"{tid}: meta_hit: {mh} expected: {beh['expect_meta_hit']}"

        status = "VALID" if got_luhn else "INVALID"

        token_field = "-"
        if beh["expect_token"]:
            tok64 = await wait_for_token64_stream(dut)
            token_field = f"0x{tok64:016x}"
            if pan in last_token_for_pan:
                prev = last_token_for_pan[pan]
                assert tok64 != prev, f"{tid}: token64 did not change with different nonce"
            last_token_for_pan[pan] = tok64
        else:
            await assert_no_token_stream(dut)

        print(f"{pan:<19} | {status:<7} | {BRAND_STR.get(b,'?'):<11} | {TYPE_STR.get(t,'?'):<8} | {ISSUER_STR.get(iss,'?'):<10} | {token_field}")