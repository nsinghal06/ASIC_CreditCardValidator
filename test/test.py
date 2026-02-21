import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

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

@cocotb.test()
async def pan_stream_basic(dut):
    # start clock
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # init
    dut.start.value = 0
    dut.pan_end.value = 0
    dut.digit_valid.value = 0
    dut.digit_in.value = 0
    dut.abort.value = 0

    await reset_dut(dut)

    # start capture
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # 16 digits example
    digits = [4,5,5,6,7,3,7,5,8,6,9,8,5,5,4,3]
    for i, d in enumerate(digits):
        await send_digit(dut, d, last=(i == len(digits)-1))

    # wait 1 cycle
    await RisingEdge(dut.clk)

    # checks
    assert int(dut.len_final.value) == 16, f"len_final={int(dut.len_final.value)}"
    assert int(dut.length_ok.value) == 1, "length_ok should be 1"
    assert int(dut.digit_ok.value) == 1, "digit_ok should be 1"
    assert int(dut.error_flag.value) == 0, "error_flag should be 0"
    # card_done is a pulse; it likely happened on end cycle.
    assert int(dut.pan_ready.value) == 1, "pan_ready should be 1"

    # IIN prefix nibble packing check (first 6 digits)
    iin = int(dut.iin_prefix.value)
    def nib(i): return (iin >> (4*i)) & 0xF
    assert nib(0) == 4
    assert nib(1) == 5
    assert nib(2) == 5
    assert nib(3) == 6
    assert nib(4) == 7
    assert nib(5) == 3