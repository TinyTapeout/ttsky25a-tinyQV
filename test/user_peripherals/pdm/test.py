# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Edge

from tqv import TinyQV

# When submitting your design, change this to the peripheral number
# in peripherals.v.  e.g. if your design is i_user_peri05, set this to 5.
# The peripheral number is not used by the test harness.
PERIPHERAL_NUM = 10

# Periphreal register definitions
# ref docs/info.md
REG_CTRL = 0x00
REG_CLKP = 0x04
REG_PCMW = 0x08

# Pin definitions, ref docs/info.md
PIN_PDM_CLK = 0x01 # uo1


PDM_DOWNSAMPLE_MAX = 64 # max downsample ratio in PDM to PCM conversion (number of PDM clocks per PCM sample)

async def assert_pin_stable(pin, clock, n_cycles):
    """Helper to check pin stability over n clock cycles"""
    initial_value = pin.value

    for cycle in range(n_cycles):
        await RisingEdge(clock)
        assert pin.value == initial_value, \
            f"Pin changed from {initial_value} to {pin.value} at cycle {cycle+1}"

async def assert_interrupt_stable(tqv, clock, n_cycles):
    """Helper to check pin stability over n clock cycles"""
    initial_value = await tqv.is_interrupt_asserted()

    for cycle in range(n_cycles):
        await RisingEdge(clock)
        value = await tqv.is_interrupt_asserted()
        assert value == initial_value, \
            f"Interrupt changed from {initial_value} to {value} at cycle {cycle+1}"

@cocotb.test()
async def test_initial(dut):
    dut._log.info("test_initial start")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    # Interact with your design's registers through this TinyQV class.
    tqv = TinyQV(dut, PERIPHERAL_NUM)

    # Reset
    await tqv.reset()

    # Initially the control register is all 0
    assert await tqv.read_word_reg(REG_CTRL) == 0x0

    # Intially the clock scaling is 0
    assert await tqv.read_word_reg(REG_CLKP) == 0x0

    # Intially the PCM sample is undefined
    pcm = await tqv.read_word_reg(REG_PCMW)
    dut._log.info(f"REG_PCMW = {pcm}")

    # Set the clock scaling, and read it back
    max_clock_scale = 64
    for clock_scale in range(1, max_clock_scale+1):
        await tqv.write_word_reg(REG_CLKP, clock_scale)
        assert await tqv.read_word_reg(REG_CLKP) == clock_scale


    # PDM clock is initially disabled
    assert dut.uo_out[PIN_PDM_CLK].value == 0
    # PDM clock does not change
    await assert_pin_stable(dut.uo_out[PIN_PDM_CLK], dut.clk, max_clock_scale*2)

    # There are no interrupts
    assert await tqv.is_interrupt_asserted() == False
    await assert_interrupt_stable(tqv, dut.clk, max_clock_scale*PDM_DOWNSAMPLE_MAX*2)

@cocotb.test()
async def test_running(dut):
    dut._log.info("test_running start")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    # Interact with your design's registers through this TinyQV class.
    tqv = TinyQV(dut, PERIPHERAL_NUM)

    # Reset
    await tqv.reset()

    # initially we are off
    assert await tqv.read_word_reg(REG_CTRL) == 0x00

    # Test on a couple different clock scaling settings
    clock_scales = range(2, 64+1, 2)
    for clock_scale in clock_scales:
        dut._log.info(f"start with scale={clock_scale}")

        # Set a clock scaling
        await tqv.write_word_reg(REG_CLKP, clock_scale)
        assert await tqv.read_word_reg(REG_CLKP) == clock_scale

        # Start the clock
        await tqv.write_word_reg(REG_CTRL, 0x01)
        assert await tqv.read_word_reg(REG_CTRL) == 0x01

        # Wait until next falling edge
        for i in range(1000):
            if dut.uo_out[PIN_PDM_CLK].value == 1:
                break
            await ClockCycles(dut.clk, 1)
        for i in range(1000):
            if dut.uo_out[PIN_PDM_CLK].value == 0:
                break
            await ClockCycles(dut.clk, 1)

        # PDM clock should toggle every SCALE clocks
        assert dut.uo_out[PIN_PDM_CLK].value == 0
        await ClockCycles(dut.clk, clock_scale//2)
        assert dut.uo_out[PIN_PDM_CLK].value == 1
        await ClockCycles(dut.clk, clock_scale//2)
        assert dut.uo_out[PIN_PDM_CLK].value == 0

        # TODO(mastensg): fix this :)
        ### # Interrupt should happen every DOWNSCAMPLE*SCALE clocks
        ### downsample = 64
        ### # Wait until next falling edge of interrupt
        ### for i in range(100000):
        ###     if await tqv.is_interrupt_asserted() == True:
        ###         break
        ###     await ClockCycles(dut.clk, 1)
        ### for i in range(100000):
        ###     if await tqv.is_interrupt_asserted() == False:
        ###         break
        ###     await ClockCycles(dut.clk, 1)
        ### assert await tqv.is_interrupt_asserted() == False
        ### await ClockCycles(dut.clk, downsample*clock_scale//2)
        ### assert await tqv.is_interrupt_asserted() == True

        # Should be a valid PCM sample
        pcm = await tqv.read_word_reg(REG_PCMW)
        dut._log.info(f"REG_PCMW = {pcm}")

