# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

# When submitting your design, change this to 16 + the peripheral number
# in peripherals.v.  e.g. if your design is i_user_simple00, set this to 16.
# The peripheral number is not used by the test harness.
PERIPHERAL_NUM = 26

gate_level = 'GATES' in os.environ
integration = 'user_peripherals' in os.environ['MODULE']

@cocotb.test(skip=(gate_level or integration))
async def test_fp_counter(dut):

    await cocotb.start(Clock(dut.clk, 1, units="ns").start())

    dut.rst_n.value = 0
    dut.fp_step.value = 112
    dut.fp_step_en.value = 0
    await ClockCycles(dut.clk, 1)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
    dut.fp_step_en.value = 1

    i = 0
    last = -1
    while True:
        await ClockCycles(dut.clk, 1)
        current = dut.fp_value.value
        if current != last:
            if current == 0:
                if last != -1:
                    break
            assert current == last + 1
            last = current
        if i % 16384 == 0:
            print(current, int(current), i)
        i += 1

    assert current == 0

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    # Interact with your design's registers through this TinyQV class.
    # This will allow the same test to be run when your design is integrated
    # with TinyQV - the implementation of this class will be replaces with a
    # different version that uses Risc-V instructions instead of the SPI 
    # interface to read and write the registers.
    tqv = TinyQV(dut, PERIPHERAL_NUM)

    # Reset, always start the test by resetting TinyQV
    await tqv.reset()

    dut._log.info("Test project behavior")

    # Test register write and read back
    await tqv.write_reg(0, 112)
    await tqv.write_reg(1, 128)
    await tqv.write_reg(2, 144)
    await tqv.write_reg(4, 240)
    await tqv.write_reg(5, 1)

    last = dut.uo_out.value
    count_rep = 1
    count_c1 = 0
    count_c2 = 0
    count_c3 = 0
    for i in range(16384):
        dut.ui_in[1].value = dut.uo_out[1].value
        await ClockCycles(dut.clk, 1)
        current = dut.uo_out.value
        count_c1 += dut.uo_out[1].value
        count_c2 += dut.uo_out[2].value
        count_c3 += dut.uo_out[3].value
        if current == last:
            count_rep += 1
        else:
            print(last, count_rep)
            last = current
            count_rep = 1

    print(last, count_rep)

    assert count_c1 == 2048
    assert count_c2 == 8192
    assert count_c3 == 16384 - 2048
    assert await tqv.read_reg(3) == 112
