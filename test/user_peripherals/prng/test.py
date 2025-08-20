# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

# When submitting your design, change this to the peripheral number
# in peripherals.v.  e.g. if your design is i_user_peri05, set this to 5.
# The peripheral number is not used by the test harness.
PERIPHERAL_NUM = 35

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    # Interact with your design's registers through this TinyQV class.
    # This will allow the same test to be run when your design is integrated
    # with TinyQV - the implementation of this class will be replaces with a
    # different version that uses Risc-V instructions instead of the SPI test
    # harness interface to read and write the registers.
    tqv = TinyQV(dut, PERIPHERAL_NUM)

    # Reset
    await tqv.reset()

    dut._log.info("Test project behavior")

    # check the 1st generated pseudo-random number
    rnd = await tqv.read_word_reg(0)
    assert rnd == 0xFEF316C3

    # check the 2nd generated pseudo-random number
    rnd = await tqv.read_word_reg(0)
    assert rnd == 0xBFC92848

    # set RNG state registers to 0
    await tqv.write_word_reg(1, 0)
    await tqv.write_word_reg(2, 0)
    await tqv.write_word_reg(3, 0)
    await tqv.write_word_reg(4, 0)

    # force update
    await tqv.read_word_reg(0)
    # confirm that the generated number is 0
    rnd = await tqv.read_word_reg(0)
    assert rnd == 0

    # set RNG state registers to original hardcoded values
    await tqv.write_word_reg(1, 0x0D1929D2)
    await tqv.write_word_reg(2, 0x491DFB74)
    await tqv.write_word_reg(3, 0x473E5E7D)
    await tqv.write_word_reg(4, 0xD6CA8A07)

    # force update
    await tqv.read_word_reg(0)
    # confirm first generated pseudo-random number
    rnd = await tqv.read_word_reg(0)
    assert rnd == 0xFEF316C3
