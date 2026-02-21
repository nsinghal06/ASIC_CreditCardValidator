# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

def pack_ui(digit=0, valid=0, start=0, end=0, mode=0):
    """Pack signals into ui_in[7:0]."""
    return ((mode & 1) << 7) | ((end & 1) << 6) | ((start & 1) << 5) | ((valid & 1) << 4) | (digit & 0xF)

async def reset_dut(dut, cycles=5):
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

async def send_pan(dut, digits, mode=0):
    """
    Send a list of decimal digits through the ui_in protocol.
    start is asserted on the first digit, end on the last digit.
    """
    n = len(digits)
    assert n >= 1

    for i, d in enumerate(digits):
        start = 1 if i == 0 else 0
        end   = 1 if i == n - 1 else 0
        dut.ui_in.value = pack_ui(digit=d, valid=1, start=start, end=end, mode=mode)
        await RisingEdge(dut.clk)

    # Go idle after sending
    dut.ui_in.value = pack_ui(valid=0, mode=mode)
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_module1_framer_16_digits(dut):
    # Start clock (tb.v already has a clock, but this keeps cocotb happy if needed)
    # If tb.v already drives clk, cocotb Clock() won't hurt, but you can comment it out if double-clocked.
    try:
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    except Exception:
        pass

    await reset_dut(dut)

    # Example 16-digit PAN (digits only; doesn't need to be a real card for Module 1)
    pan_digits = [4, 5, 3, 9, 1, 4, 8, 8, 0, 3, 4, 3, 6, 4, 6, 7]

    # Send it
    await send_pan(dut, pan_digits, mode=0)

    # ---- Check debug outputs (based on the suggested mapping) ----
    # uo_out[0] = card_done pulse
    # uo_out[3] = length_ok
    # uo_out[2] = iin_ready
    # uo_out[5] = error_flag

    uo = int(dut.uo_out.value)

    card_done  = (uo >> 0) & 1
    iin_ready  = (uo >> 2) & 1
    length_ok  = (uo >> 3) & 1
    error_flag = (uo >> 5) & 1

    # card_done is a 1-cycle pulse — depending on timing it may have pulsed the previous cycle.
    # So we check it *around* the end: look for it over a few cycles.
    saw_done = False
    for _ in range(4):
        uo_now = int(dut.uo_out.value)
        if (uo_now & 1) == 1:
            saw_done = True
            break
        await RisingEdge(dut.clk)

    assert saw_done, "Expected card_done pulse (uo_out[0]) but did not see it"

    # Length should be ok for 16 digits (13..19 range)
    # length_ok should be 1 after end
    assert length_ok == 1, f"Expected length_ok=1 for 16 digits, got {length_ok}"

    # After 6+ digits, iin_ready should be 1
    assert iin_ready == 1, f"Expected iin_ready=1 after prefix capture, got {iin_ready}"

    # Should not have protocol errors in this test
    assert error_flag == 0, f"Expected error_flag=0, got {error_flag}"

@cocotb.test()
async def test_bad_length_should_fail_length_ok(dut):
    try:
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    except Exception:
        pass

    await reset_dut(dut)

    # Too short: 12 digits
    pan_digits = [1,2,3,4,5,6,7,8,9,0,1,2]
    await send_pan(dut, pan_digits, mode=0)

    uo = int(dut.uo_out.value)
    length_ok = (uo >> 3) & 1
    assert length_ok == 0, f"Expected length_ok=0 for 12 digits, got {length_ok}"
