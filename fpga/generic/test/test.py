# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: MIT

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_run(dut):
    dut._log.info("Start")

    # Set the clock period to 71.4 ns (14 MHz)
    clock = Clock(dut.clk, 71.428, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")

    # ui_in[0] == 0: Output is uio_in
    dut.ui_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    await ClockCycles(dut.clk, 65536)
