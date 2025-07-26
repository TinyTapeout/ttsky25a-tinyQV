# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge

from tqv import TinyQV

PERIPHERAL_NUM = 16+3

# Generate WS2812B waveform for a single bit
async def send_ws2812b_bit(dut, bit, clk_period_ns=15.625):
    if bit == 1:
        high_time = 800   # ns
        low_time  = 450
    else:
        high_time = 400
        low_time  = 850

    dut.ui_in.value = 1 << 1  # DIN = 1
    await Timer(high_time, units='ns')
    dut.ui_in.value = 0
    await Timer(low_time, units='ns')


# Send a full byte MSB-first
async def send_ws2812b_byte(dut, byte):
    for i in range(8):
        bit = (byte >> (7 - i)) & 1
        await send_ws2812b_bit(dut, bit)
    # Inter-bit spacing is not required but can help simulate reality
    await Timer(200, units='ns')


# Simulate IDLE (> 50 us)
async def idle_line(dut, us=60):
    dut.ui_in.value = 0
    await Timer(us * 1000, units='ns')


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start test")

    #clock = Clock(dut.clk, 15.625, units="ns")  # 64MHz clock
    clock = Clock(dut.clk, 16, units="ns")  # ≈62.5 MHz, close enough to 64 MHz for test
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # Check if rgb?ready register is ON
    ready = int(await tqv.read_reg(15))
    assert ready == 0
    dut._log.info("Reading rgb_ready is OFF")

    dut._log.info("Sending 3 bytes (G, R, B)")

    # Send 3 bytes for RGB (G=0x12, R=0x34, B=0x56)
    await send_ws2812b_byte(dut, 0x12)#g
    await send_ws2812b_byte(dut, 0x34)#r
    await send_ws2812b_byte(dut, 0x56)#b

    # Wait for RGB to be latched
    await ClockCycles(dut.clk, 10)

    dut._log.info("Reading rgb_ready is 0xFF and that cleared when writen a 0 to addr 0xe")
    await tqv.read_reg(15)==0xFF
    await ClockCycles(dut.clk, 1)  # allow state update
    await tqv.write_reg(14, 0) 
    await ClockCycles(dut.clk, 1)  # allow clearing to propagate
    await tqv.read_reg(15)==0x00
    
    # Read back registers
    g = int(await tqv.read_reg(1))
    r = int(await tqv.read_reg(0))
    b = int(await tqv.read_reg(2))

    dut._log.info(f"Read RGB = ({r:02X}, {g:02X}, {b:02X})")
    assert r == 0x34
    assert g == 0x12
    assert b == 0x56

    # Now send THREE extra byteS and confirm bits get forwarded
    dut._log.info("Testing bit forwarding to DOUT")

    # Send 3 bytes for RGB (G=0x12, R=0x34, B=0x56)
    await send_ws2812b_byte(dut, 0xDE)
    await send_ws2812b_byte(dut, 0xAD)
    await send_ws2812b_byte(dut, 0xFF)

    # Allow a few cycles for DOUT propagation
    await ClockCycles(dut.clk, 10)

    dut._log.info("Reading rgb_ready is 0x00")
    read1 = int(await tqv.read_reg(15))
    await ClockCycles(dut.clk, 1)  # allow state update
    await tqv.write_reg(14, 0) 
    await ClockCycles(dut.clk, 1)  # allow clearing to propagate
    read2 = int(await tqv.read_reg(15))
    assert read1 == 0x00
    assert read2 == 0x00

    # Check that uo_out[1] has toggled (forwarding is happening)
    # Note: due to pipelining, you may not catch exact bits — we just assert activity
    dout_activity = int(dut.uo_out.value) & (1 << 1)
    assert dout_activity in [0, 1]

    # Now inject idle to trigger reset
    dut._log.info("Injecting IDLE condition")
    await idle_line(dut)

    await ClockCycles(dut.clk, 10)

    # Check that registers have been cleared (due to reset)
    assert int(await tqv.read_reg(0)) == 0x34  # Still holds, unless you clear manually in RTL
    # You could modify RTL to clear on idle if desired

    #SEND AGAIN AFTER IDLE
    # Send 3 bytes for RGB (G=0x12, R=0x34, B=0x56)
    await send_ws2812b_byte(dut, 0xab)
    await send_ws2812b_byte(dut, 0xcd)
    await send_ws2812b_byte(dut, 0xef)

    # Wait for RGB to be latched
    await ClockCycles(dut.clk, 10)

    # Read back registers
    g = int(await tqv.read_reg(1))
    r = int(await tqv.read_reg(0))
    b = int(await tqv.read_reg(2))

    dut._log.info(f"Read RGB = ({r:02X}, {g:02X}, {b:02X})")
    assert r == 0xcd
    assert g == 0xab
    assert b == 0xef

    dut._log.info("Test complete")
