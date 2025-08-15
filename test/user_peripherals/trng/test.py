# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

PERIPHERAL_NUM = 10

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

    # Reset
    await tqv.reset()

    dut._log.info("Test TRNG peripheral behavior")
    # Register addresses
    CONTROL_REG = 0x0
    STATUS_REG = 0x1
    CALIBRATION_CYCLES_REG = 0x2
    I1_REG = 0x3
    I2_REG = 0x4
    TRIGGER_REG = 0x5
    CLK_DIVISION_REG = 0x6 #TinyQV runs at 64MHz, it is nice to have a clock divider to run at lower frequencies
    RANDOM_NUMBER_REG = 0x7

    # Control register bits
    RESET = 0x1 << 0
    CORE_ENABLE = 0x1 << 1
    SEL_BASE_SHORT = 0x1 << 2
    CALIBRATION = 0x1 << 3
    READ_REQUEST = 0x1 << 4
    READY = 0x1 << 0

    # Parameters for the TRNG peripheral
    # These values can be adjusted based on the test case
    ENTROPY_CELLS = 0x1 # 24-bit entropy cells
    SELECT_BASE_SHORT = False # Set to True to select the short base, False for the long base

    #=== Step 1: Reset TRNG peripheral ===#
    dut._log.info("----------------------------------")
    dut._log.info("Step 1: Reset TRNG peripheral")
    await tqv.write_word_reg(CONTROL_REG, RESET | CORE_ENABLE) # Reset and enable the TRNG peripheral
    await ClockCycles(dut.clk, 1000) # Reset the TRNG for 1000 clock cycles
    await tqv.write_word_reg(CONTROL_REG, CORE_ENABLE)
    await tqv.write_word_reg(CLK_DIVISION_REG, 0x10) # Set clock division factor to 16 
    
    control_reg = await tqv.read_word_reg(CONTROL_REG)
    dut._log.info(f"TRNG control register after reset: {control_reg:#x}")
    status_reg = await tqv.read_word_reg(STATUS_REG)
    dut._log.info(f"TRNG status register after reset: {status_reg:#x}")

    #=== Step 2: Trigger entropy cells and select ring generator base ===#
    dut._log.info("----------------------------------")
    dut._log.info("Step 2: Trigger entropy cells")
    await tqv.write_word_reg(I1_REG, ENTROPY_CELLS)
    await tqv.write_word_reg(I2_REG, 0x0) # opposite of I1_REG
    await tqv.write_word_reg(TRIGGER_REG, ENTROPY_CELLS)
    await ClockCycles(dut.clk, 10) # Wait for the trigger to take effect
    dut._log.info(f"Triggered entropy cells: {ENTROPY_CELLS:#x}")

    # Select the ring generator base
    if(SELECT_BASE_SHORT):
        dut._log.info("Selecting ring generator base short")
        control_reg = await tqv.read_word_reg(CONTROL_REG)
        await tqv.write_word_reg(CONTROL_REG, SEL_BASE_SHORT | control_reg)
    else:
        dut._log.info("Default selecing ring generator base long")
 

    #=== Step 3: Calibrate TRNG peripheral ===#
    dut._log.info("----------------------------------")
    dut._log.info("Step 3: Calibrate TRNG peripheral")
    
    # Set the number of calibration cycles
    calibration_cycles = 0x1 << 11  # Example: 2^11 cycles
    await tqv.write_word_reg(CALIBRATION_CYCLES_REG, calibration_cycles)  # Set calibration cycles
    cycle_reg = await tqv.read_word_reg(CALIBRATION_CYCLES_REG) # read out the value to verify and print it
    assert cycle_reg == calibration_cycles
    dut._log.info(f"Set calibration cycle: {calibration_cycles} - Read out calibration cycles: {cycle_reg}")    
    
    # Trigger calibration
    control_reg = await tqv.read_word_reg(CONTROL_REG)
    await tqv.write_word_reg(CONTROL_REG, CALIBRATION | control_reg)
    
    timeout = calibration_cycles*2  # Set a timeout for calibration
    status_reg = await tqv.read_word_reg(STATUS_REG)
    # if the calibration cycles is too short, the ready signal will asserted
    dut._log.info(f"TRNG status before loop: {status_reg:#x}") 
    # Wait for ready signal to be asserted
    while (await tqv.read_word_reg(STATUS_REG) & READY) == 0:
        status_reg = await tqv.read_word_reg(STATUS_REG)
        # dut._log.info(f"TRNG status during calibration: {status_reg:#x}")
        await ClockCycles(dut.clk, 1)
        timeout -= 1
        if timeout <= 0:
            raise TimeoutError("TRNG calibration timed out")
    
    dut._log.info("TRNG peripheral is ready after calibration")

    #=== Step 4: Read TRNG output ===#
    dut._log.info("----------------------------------")
    dut._log.info("Step 4: Read TRNG output")
    control_reg = await tqv.read_word_reg(CONTROL_REG)
    await tqv.write_word_reg(CONTROL_REG, READ_REQUEST | control_reg) 

    # Maybe the time out is not necessary here
    # By the time we reach here, the ready signal should be asserted
    timeout = 32*2  # The ready signal should be asserted within 32 cycles for reading out 32-bit random data
    while (await tqv.read_word_reg(STATUS_REG) & READY) == 0:
        # status_reg = await tqv.read_word_reg(STATUS_REG)
        await ClockCycles(dut.clk, 1)
        timeout -= 1
        if timeout <= 0:
            raise TimeoutError("TRNG read request timed out") 
    dut._log.info("TRNG read request completed")

    # Read the random data
    random_data = await tqv.read_word_reg(RANDOM_NUMBER_REG)
    # Deassert the read request
    control_reg = await tqv.read_word_reg(CONTROL_REG)
    await tqv.write_word_reg(CONTROL_REG, control_reg & ~READ_REQUEST)
    dut._log.info(f"TRNG random data: 0x{random_data:08x}")

    #=== Step 5: Repeat to read several random numbers ===#
    dut._log.info("----------------------------------")
    dut._log.info("Step 5: Repeat to read several random numbers")
    for i in range(5):
        control_reg = await tqv.read_word_reg(CONTROL_REG)
        await tqv.write_word_reg(CONTROL_REG, READ_REQUEST | control_reg)

        # Again, maybe the time out is not necessary here
        timeout = 32*2  # The ready signal should be asserted within 32 cycles for reading out 32-bit random data
        while (await tqv.read_word_reg(STATUS_REG) & READY) == 0:
            # status_reg = await tqv.read_word_reg(STATUS_REG)
            await ClockCycles(dut.clk, 1)
            timeout -= 1
            if timeout <= 0:
                raise TimeoutError("TRNG read request timed out") 

        random_data = await tqv.read_word_reg(RANDOM_NUMBER_REG) # Read the random data
        control_reg = await tqv.read_word_reg(CONTROL_REG) # Deassert the read request

        await tqv.write_word_reg(CONTROL_REG, control_reg & ~READ_REQUEST)
        dut._log.info(f"TRNG random data {i+1}: 0x{random_data:08x}")
    dut._log.info("Test completed successfully")