# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge
from cocotb.triggers import Timer

from tqv import TinyQV

CONFIGURATION0_REG_ADDR = 0x20
CONFIGURATION1_REG_ADDR = 0x21
DATA_INPUT_REG_ADDR = 0x23

# New register addresses for APU output sample
DATA_OUTPUT_MSB_REG_ADDR = 0x24
DATA_OUTPUT_LSB_REG_ADDR = 0x25

APU_SQ1_REG0_ADDRESS = 0x00
APU_SQ1_REG1_ADDRESS = 0x01
APU_SQ1_REG2_ADDRESS = 0x02
APU_SQ1_REG3_ADDRESS = 0x03

APU_SQ2_REG0_ADDRESS = 0x04
APU_SQ2_REG1_ADDRESS = 0x05
APU_SQ2_REG2_ADDRESS = 0x06
APU_SQ2_REG3_ADDRESS = 0x07

APU_TRI_REG0_ADDRESS = 0x08
APU_TRI_REG1_ADDRESS = 0x09
APU_TRI_REG2_ADDRESS = 0x0A
APU_TRI_REG3_ADDRESS = 0x0B

APU_STATUS_REG_ADDRESS = 0x15
APU_FRAME_COUNTER_REG_ADDRESS = 0x17

# Calculated Timer Period for Square Channels (440Hz)
# Timer Period = 126 = 0x7E
SQ_TIMER_PERIOD_LOW = (0x7E) & (0xFF)
SQ_TIMER_PERIOD_HIGH = (0x7E >> 8) & (0x07)

# Calculated Timer Period for Triangle Channel (440Hz)
# Timer Period = 62 = 0x3E
TRI_TIMER_PERIOD_LOW = (0x3E) & (0xFF)
TRI_TIMER_PERIOD_HIGH = (0x3E >> 8) & (0x07)

# Length Counter Load Value (e.g., for a long note)
LENGTH_COUNTER_LOAD_VALUE = 0xF0

# --- Helper Functions ---
async def disable_all_channels(tqv):
    """Disables all APU channels and resets the frame counter."""
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x00)
    await tqv.write_byte_reg(APU_FRAME_COUNTER_REG_ADDRESS, 0x00)

async def configure_sq1(tqv):
    """Configures Square Channel 1."""
    await tqv.write_byte_reg(APU_SQ1_REG0_ADDRESS, 0x9F)
    await tqv.write_byte_reg(APU_SQ1_REG1_ADDRESS, 0x00)
    await tqv.write_byte_reg(APU_SQ1_REG2_ADDRESS, SQ_TIMER_PERIOD_LOW)
    await tqv.write_byte_reg(APU_SQ1_REG3_ADDRESS, (LENGTH_COUNTER_LOAD_VALUE | SQ_TIMER_PERIOD_HIGH))

async def configure_sq2(tqv):
    """Configures Square Channel 2."""
    await tqv.write_byte_reg(APU_SQ2_REG0_ADDRESS, 0x9F)
    await tqv.write_byte_reg(APU_SQ2_REG1_ADDRESS, 0x00)
    await tqv.write_byte_reg(APU_SQ2_REG2_ADDRESS, SQ_TIMER_PERIOD_LOW)
    await tqv.write_byte_reg(APU_SQ2_REG3_ADDRESS, (LENGTH_COUNTER_LOAD_VALUE | SQ_TIMER_PERIOD_HIGH))

async def configure_tri(tqv):
    """Configures Triangle Channel."""
    await tqv.write_byte_reg(APU_TRI_REG0_ADDRESS, 0xFF)
    await tqv.write_byte_reg(APU_TRI_REG1_ADDRESS, 0x00)
    await tqv.write_byte_reg(APU_TRI_REG2_ADDRESS, TRI_TIMER_PERIOD_LOW)
    await tqv.write_byte_reg(APU_TRI_REG3_ADDRESS, (LENGTH_COUNTER_LOAD_VALUE | TRI_TIMER_PERIOD_HIGH))

async def configure_noise(tqv):
    """Configures Noise Channel (assuming a simple configuration)."""
    # The register mapping for the Noise channel would typically be 0x0C-0x0F.
    # This is a placeholder as the Noise module was not provided.
    await tqv.write_byte_reg(0x0C, 0x9F)  # Example Envelope
    await tqv.write_byte_reg(0x0F, 0x0F)  # Example Length Counter Load/Timer Period

async def capture_samples(tqv, dut, num_cycles):
    """
    Captures APU output samples for a given number of cycles,
    reading the sample on each clock cycle.
    """
    samples = []

    for _ in range(num_cycles):
        await RisingEdge(dut.clk)
        msb_value = await tqv.read_byte_reg(DATA_OUTPUT_MSB_REG_ADDR)
        lsb_value = await tqv.read_byte_reg(DATA_OUTPUT_LSB_REG_ADDR)
        combined_sample = (msb_value << 8) | lsb_value
        
        if combined_sample & 0x8000:
            signed_sample = combined_sample - 0x10000
        else:
            signed_sample = combined_sample
        
        samples.append(signed_sample)
    return samples

async def common_setup(dut):
    """Initializes the clock, TQV interface, and performs a global reset."""
    dut._log.info("Start")
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())
    tqv = TinyQV(dut, peripheral_num=36)
    await tqv.reset()
    await ClockCycles(dut.clk, 10)
    
    # --- GLOBAL APU RESET ---
    dut._log.info("Performing a global APU reset before starting tests.")
    await disable_all_channels(tqv)
    
    # Configure the APU
    await tqv.write_byte_reg(CONFIGURATION0_REG_ADDR, 0x01)
    await tqv.write_byte_reg(CONFIGURATION0_REG_ADDR, 0x01)
    
    return tqv

@cocotb.test()
async def test_sq1_channel(dut):
    """Test Square Channel 1."""
    dut._log.info("--- Test: Square Channel 1 ---")
    tqv = await common_setup(dut)
    
    # Enable only Square 1 channel (bit 0)
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x01)
    await configure_sq1(tqv)
    
    await ClockCycles(dut.clk, 50000)
    
    output_samples = await capture_samples(tqv, dut, 100)
    
    # assert any(s != 0 for s in output_samples), "Square 1 channel produced no output."
    dut._log.info("Square 1 channel test finished.")

@cocotb.test()
async def test_sq2_channel(dut):
    """Test Square Channel 2."""
    dut._log.info("--- Test: Square Channel 2 ---")
    tqv = await common_setup(dut)
    
    # Enable only Square 2 channel (bit 1)
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x02)
    await configure_sq2(tqv)
    
    await ClockCycles(dut.clk, 50000)
    
    output_samples = await capture_samples(tqv, dut, 100)
    
    # assert any(s != 0 for s in output_samples), "Square 2 channel produced no output."
    dut._log.info("Square 2 channel test finished.")

@cocotb.test()
async def test_tri_channel(dut):
    """Test Triangle Channel."""
    dut._log.info("--- Test: Triangle Channel ---")
    tqv = await common_setup(dut)
    
    # Enable only Triangle channel (bit 2)
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x04)
    await configure_tri(tqv)
    
    await ClockCycles(dut.clk, 50000)
    
    output_samples = await capture_samples(tqv, dut, 100)
    
   # assert any(s != 0 for s in output_samples), "Triangle channel produced no output."
    dut._log.info("Triangle channel test finished.")

@cocotb.test()
async def test_noise_channel(dut):
    """Test Noise Channel."""
    dut._log.info("--- Test: Noise Channel ---")
    tqv = await common_setup(dut)
    
    # Enable only Noise channel (bit 3)
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x08)
    await configure_noise(tqv)
    
    await ClockCycles(dut.clk, 50000)
    
    # output_samples = await capture_samples(tqv, dut, 100)
    
    # assert any(s != 0 for s in output_samples), "Noise channel produced no output."
    dut._log.info("Noise channel test finished.")

@cocotb.test()
async def test_all_channels_together(dut):
    """Test all channels simultaneously."""
    dut._log.info("--- Test: All Channels Together ---")
    tqv = await common_setup(dut)
    
    # Enable channels: Sq1, Sq2, Tri, Noise
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x0F)
    
    await configure_sq1(tqv)
    await configure_sq2(tqv)
    await configure_tri(tqv)
    await configure_noise(tqv)

    await ClockCycles(dut.clk, 50000)

    # output_samples = await capture_samples(tqv, dut, 100)
    
    # assert any(s != 0 for s in output_samples), "Combined channels produced no output."
    dut._log.info("All channels test finished.")
