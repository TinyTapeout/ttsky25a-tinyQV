# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

# When submitting your design, change this to 16 + the peripheral number
# in peripherals.v.  e.g. if your design is i_user_simple00, set this to 16.
# The peripheral number is not used by the test harness.
PERIPHERAL_NUM = 23

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
    await tqv.write_reg(0, 20)
    await tqv.write_reg(1, 30)
    await tqv.write_reg(2, 40)
    assert await tqv.read_reg(0) == 20
    assert await tqv.read_reg(1) == 30
    assert await tqv.read_reg(2) == 40

    # Keep testing the module by changing the input values, waiting for
    # one or more clock cycles, and asserting the expected output values.
    await tqv.reset()
    assert await tqv.read_reg(0) == 0x00
    assert await tqv.read_reg(1) == 0xF0
    assert await tqv.read_reg(2) == 0xF0
    assert await tqv.read_reg(3) == 0x00
    assert await tqv.read_reg(4) == 0x3F
    assert await tqv.read_reg(5) == 0x80

    async def test_ubcd(rbi, bi, lt, al, version, extras, value, data, rbo):
        await tqv.write_reg(0, value)
        await tqv.write_reg(1, (rbi << 7) | (lt << 6) | (bi << 5) | (al << 4))
        await tqv.write_reg(2, (extras << 5) | version)
        await tqv.write_reg(3, 0)
        assert (dut.uo_out.value & 0x7F) == data
        assert (await tqv.read_reg(4) & 0x7F) == data
        assert (await tqv.read_reg(5) & 0xF0) == (rbo << 7) | (0x40 if value >= 10 else 0)

    # BCD RCA/blanking version
    await test_ubcd(1, 1, 1, 1, 0, 0, 15, 0x00, 1)
    await test_ubcd(1, 1, 1, 1, 0, 0, 14, 0x00, 1)
    await test_ubcd(1, 1, 1, 1, 0, 0, 11, 0x00, 1)
    await test_ubcd(1, 1, 1, 1, 0, 0, 10, 0x00, 1)
    await test_ubcd(1, 1, 1, 1, 0, 0,  9, 0x67, 1)
    await test_ubcd(1, 1, 1, 1, 0, 0,  8, 0x7F, 1)
    await test_ubcd(1, 1, 1, 1, 0, 0,  7, 0x07, 1)
    await test_ubcd(1, 1, 1, 1, 0, 0,  6, 0x7C, 1)
    await test_ubcd(1, 1, 1, 1, 0, 0,  1, 0x06, 1)
    await test_ubcd(1, 1, 1, 1, 0, 0,  0, 0x3F, 1)

    # BCD TI version
    await test_ubcd(1, 1, 1, 1, 1, 1, 15, 0x00, 1)
    await test_ubcd(1, 1, 1, 1, 1, 1, 14, 0x78, 1)
    await test_ubcd(1, 1, 1, 1, 1, 1, 11, 0x4C, 1)
    await test_ubcd(1, 1, 1, 1, 1, 1, 10, 0x58, 1)
    await test_ubcd(1, 1, 1, 1, 1, 1,  9, 0x67, 1)
    await test_ubcd(1, 1, 1, 1, 1, 1,  8, 0x7F, 1)
    await test_ubcd(1, 1, 1, 1, 1, 1,  7, 0x07, 1)
    await test_ubcd(1, 1, 1, 1, 1, 1,  6, 0x7D, 1)

    # BCD NatSemi version
    await test_ubcd(1, 1, 1, 1, 2, 2, 15, 0x00, 1)
    await test_ubcd(1, 1, 1, 1, 2, 2, 14, 0x08, 1)
    await test_ubcd(1, 1, 1, 1, 2, 2, 11, 0x63, 1)
    await test_ubcd(1, 1, 1, 1, 2, 2, 10, 0x5C, 1)
    await test_ubcd(1, 1, 1, 1, 2, 2,  9, 0x67, 1)
    await test_ubcd(1, 1, 1, 1, 2, 2,  8, 0x7F, 1)
    await test_ubcd(1, 1, 1, 1, 2, 2,  7, 0x27, 1)
    await test_ubcd(1, 1, 1, 1, 2, 2,  6, 0x7C, 1)

    # BCD Toshiba version
    await test_ubcd(1, 1, 1, 1, 3, 3, 15, 0x6D, 1)
    await test_ubcd(1, 1, 1, 1, 3, 3, 14, 0x66, 1)
    await test_ubcd(1, 1, 1, 1, 3, 3, 11, 0x06, 1)
    await test_ubcd(1, 1, 1, 1, 3, 3, 10, 0x3F, 1)
    await test_ubcd(1, 1, 1, 1, 3, 3,  9, 0x67, 1)
    await test_ubcd(1, 1, 1, 1, 3, 3,  8, 0x7F, 1)
    await test_ubcd(1, 1, 1, 1, 3, 3,  7, 0x27, 1)
    await test_ubcd(1, 1, 1, 1, 3, 3,  6, 0x7D, 1)

    # BCD lines version
    await test_ubcd(1, 1, 1, 1, 4, 4, 15, 0x00, 1)
    await test_ubcd(1, 1, 1, 1, 4, 4, 14, 0x01, 1)
    await test_ubcd(1, 1, 1, 1, 4, 4, 11, 0x48, 1)
    await test_ubcd(1, 1, 1, 1, 4, 4, 10, 0x08, 1)
    await test_ubcd(1, 1, 1, 1, 4, 4,  9, 0x6F, 1)
    await test_ubcd(1, 1, 1, 1, 4, 4,  8, 0x7F, 1)
    await test_ubcd(1, 1, 1, 1, 4, 4,  7, 0x07, 1)
    await test_ubcd(1, 1, 1, 1, 4, 4,  6, 0x7C, 1)

    # BCD Electronika version
    await test_ubcd(1, 1, 1, 1, 5, 5, 15, 0x00, 1)
    await test_ubcd(1, 1, 1, 1, 5, 5, 14, 0x79, 1)
    await test_ubcd(1, 1, 1, 1, 5, 5, 11, 0x38, 1)
    await test_ubcd(1, 1, 1, 1, 5, 5, 10, 0x40, 1)
    await test_ubcd(1, 1, 1, 1, 5, 5,  9, 0x6F, 1)
    await test_ubcd(1, 1, 1, 1, 5, 5,  8, 0x7F, 1)
    await test_ubcd(1, 1, 1, 1, 5, 5,  7, 0x07, 1)
    await test_ubcd(1, 1, 1, 1, 5, 5,  6, 0x7D, 1)

    # BCD Code B version
    await test_ubcd(1, 1, 1, 1, 6, 6, 15, 0x00, 1)
    await test_ubcd(1, 1, 1, 1, 6, 6, 14, 0x73, 1)
    await test_ubcd(1, 1, 1, 1, 6, 6, 11, 0x79, 1)
    await test_ubcd(1, 1, 1, 1, 6, 6, 10, 0x40, 1)
    await test_ubcd(1, 1, 1, 1, 6, 6,  9, 0x6F, 1)
    await test_ubcd(1, 1, 1, 1, 6, 6,  8, 0x7F, 1)
    await test_ubcd(1, 1, 1, 1, 6, 6,  7, 0x27, 1)
    await test_ubcd(1, 1, 1, 1, 6, 6,  6, 0x7C, 1)

    # BCD hexadecimal version
    await test_ubcd(1, 1, 1, 1, 7, 7, 15, 0x71, 1)
    await test_ubcd(1, 1, 1, 1, 7, 7, 14, 0x79, 1)
    await test_ubcd(1, 1, 1, 1, 7, 7, 11, 0x7C, 1)
    await test_ubcd(1, 1, 1, 1, 7, 7, 10, 0x77, 1)
    await test_ubcd(1, 1, 1, 1, 7, 7,  9, 0x6F, 1)
    await test_ubcd(1, 1, 1, 1, 7, 7,  8, 0x7F, 1)
    await test_ubcd(1, 1, 1, 1, 7, 7,  7, 0x27, 1)
    await test_ubcd(1, 1, 1, 1, 7, 7,  6, 0x7D, 1)

    # BCD ripple blanking input
    await test_ubcd(0, 1, 1, 1, 7, 7, 15, 0x71, 1)
    await test_ubcd(0, 1, 1, 1, 7, 7, 14, 0x79, 1)
    await test_ubcd(0, 1, 1, 1, 7, 7,  1, 0x06, 1)
    await test_ubcd(0, 1, 1, 1, 7, 7,  0, 0x00, 0)

    # BCD RBI, BI, LT, AL lines
    await test_ubcd(1, 1, 1, 1, 7, 7, 1, 0x06, 1)
    await test_ubcd(1, 1, 0, 1, 7, 7, 1, 0x7F, 1)
    await test_ubcd(1, 1, 0, 0, 7, 7, 1, 0x00, 1)
    await test_ubcd(1, 0, 0, 0, 7, 7, 1, 0x7F, 0)

    # BCD RBI, BI, LT, AL lines
    await test_ubcd(0, 1, 1, 1, 7, 7, 1, 0x06, 1)
    await test_ubcd(0, 1, 0, 1, 7, 7, 1, 0x7F, 1)
    await test_ubcd(0, 1, 0, 0, 7, 7, 1, 0x00, 1)
    await test_ubcd(0, 0, 0, 0, 7, 7, 1, 0x7F, 0)

    async def test_ascii(bi, al, lc, fs, extras, value, data, ltr):
        await tqv.write_reg(0, value)
        await tqv.write_reg(1, (bi << 5) | (al << 4))
        await tqv.write_reg(2, (extras << 5) | (lc << 4) | (fs << 3))
        await tqv.write_reg(3, 2)
        assert (dut.uo_out.value & 0x7F) == data
        assert (await tqv.read_reg(4) & 0x7F) == data
        assert (await tqv.read_reg(5) & 0x70) == (ltr << 5)

    # ASCII font 0
    await test_ascii(1, 1, 1, 0, 7, 0x36, 0x7D, 1)
    await test_ascii(1, 1, 1, 0, 7, 0x37, 0x27, 1)
    await test_ascii(1, 1, 1, 0, 7, 0x38, 0x7F, 1)
    await test_ascii(1, 1, 1, 0, 7, 0x39, 0x6F, 1)
    await test_ascii(1, 1, 1, 0, 7, 0x41, 0x77, 0)
    await test_ascii(1, 1, 1, 0, 7, 0x42, 0x7C, 0)
    await test_ascii(1, 1, 1, 0, 7, 0x43, 0x39, 0)
    await test_ascii(1, 1, 1, 0, 7, 0x4F, 0x3F, 0)
    await test_ascii(1, 1, 1, 0, 7, 0x53, 0x6D, 0)
    await test_ascii(1, 1, 1, 0, 7, 0x61, 0x5F, 0)
    await test_ascii(1, 1, 1, 0, 7, 0x62, 0x7C, 0)
    await test_ascii(1, 1, 1, 0, 7, 0x63, 0x58, 0)
    await test_ascii(1, 1, 1, 0, 7, 0x6F, 0x5C, 0)
    await test_ascii(1, 1, 1, 0, 7, 0x73, 0x6D, 0)

    # ASCII font 1
    await test_ascii(1, 1, 1, 1, 0, 0x36, 0x7C, 1)
    await test_ascii(1, 1, 1, 1, 0, 0x37, 0x07, 1)
    await test_ascii(1, 1, 1, 1, 0, 0x38, 0x7F, 1)
    await test_ascii(1, 1, 1, 1, 0, 0x39, 0x67, 1)
    await test_ascii(1, 1, 1, 1, 0, 0x41, 0x77, 0)
    await test_ascii(1, 1, 1, 1, 0, 0x42, 0x7C, 0)
    await test_ascii(1, 1, 1, 1, 0, 0x43, 0x39, 0)
    await test_ascii(1, 1, 1, 1, 0, 0x4F, 0x6B, 0)
    await test_ascii(1, 1, 1, 1, 0, 0x53, 0x2D, 0)
    await test_ascii(1, 1, 1, 1, 0, 0x61, 0x44, 0)
    await test_ascii(1, 1, 1, 1, 0, 0x62, 0x7C, 0)
    await test_ascii(1, 1, 1, 1, 0, 0x63, 0x58, 0)
    await test_ascii(1, 1, 1, 1, 0, 0x6F, 0x5C, 0)
    await test_ascii(1, 1, 1, 1, 0, 0x73, 0x2D, 0)

    # ASCII font 0, uppercase only
    await test_ascii(1, 1, 0, 0, 7, 0x36, 0x7D, 1)
    await test_ascii(1, 1, 0, 0, 7, 0x37, 0x27, 1)
    await test_ascii(1, 1, 0, 0, 7, 0x38, 0x7F, 1)
    await test_ascii(1, 1, 0, 0, 7, 0x39, 0x6F, 1)
    await test_ascii(1, 1, 0, 0, 7, 0x41, 0x77, 0)
    await test_ascii(1, 1, 0, 0, 7, 0x42, 0x7C, 0)
    await test_ascii(1, 1, 0, 0, 7, 0x43, 0x39, 0)
    await test_ascii(1, 1, 0, 0, 7, 0x4F, 0x3F, 0)
    await test_ascii(1, 1, 0, 0, 7, 0x53, 0x6D, 0)
    await test_ascii(1, 1, 0, 0, 7, 0x61, 0x77, 0)
    await test_ascii(1, 1, 0, 0, 7, 0x62, 0x7C, 0)
    await test_ascii(1, 1, 0, 0, 7, 0x63, 0x39, 0)
    await test_ascii(1, 1, 0, 0, 7, 0x6F, 0x3F, 0)
    await test_ascii(1, 1, 0, 0, 7, 0x73, 0x6D, 0)

    # ASCII font 1, uppercase only
    await test_ascii(1, 1, 0, 1, 0, 0x36, 0x7C, 1)
    await test_ascii(1, 1, 0, 1, 0, 0x37, 0x07, 1)
    await test_ascii(1, 1, 0, 1, 0, 0x38, 0x7F, 1)
    await test_ascii(1, 1, 0, 1, 0, 0x39, 0x67, 1)
    await test_ascii(1, 1, 0, 1, 0, 0x41, 0x77, 0)
    await test_ascii(1, 1, 0, 1, 0, 0x42, 0x7C, 0)
    await test_ascii(1, 1, 0, 1, 0, 0x43, 0x39, 0)
    await test_ascii(1, 1, 0, 1, 0, 0x4F, 0x6B, 0)
    await test_ascii(1, 1, 0, 1, 0, 0x53, 0x2D, 0)
    await test_ascii(1, 1, 0, 1, 0, 0x61, 0x77, 0)
    await test_ascii(1, 1, 0, 1, 0, 0x62, 0x7C, 0)
    await test_ascii(1, 1, 0, 1, 0, 0x63, 0x39, 0)
    await test_ascii(1, 1, 0, 1, 0, 0x6F, 0x6B, 0)
    await test_ascii(1, 1, 0, 1, 0, 0x73, 0x2D, 0)

    # ASCII BI and AL lines
    await test_ascii(1, 1, 1, 1, 1, 0x31, 0x06, 1)
    await test_ascii(1, 0, 1, 1, 1, 0x31, 0x79, 1)
    await test_ascii(0, 0, 1, 1, 1, 0x31, 0x7F, 1)
    await test_ascii(0, 1, 1, 1, 1, 0x31, 0x00, 1)

    async def test_cistercian(bi, al, lt1, lt2, value1, value2, u1, v1, w1, x1, y1, u2, v2, w2, x2, y2):
        await tqv.write_reg(0, value1 | (value2 << 4))
        await tqv.write_reg(1, (lt1 << 6) | (bi << 5) | (al << 4))
        await tqv.write_reg(3, 4)
        assert (dut.uo_out.value & 0x1F) == u1 | (v1 << 1) | (w1 << 2) | (x1 << 3) | (y1 << 4)
        assert (await tqv.read_reg(4) & 0x1F) == u1 | (v1 << 1) | (w1 << 2) | (x1 << 3) | (y1 << 4)
        await tqv.write_reg(1, (lt2 << 6) | (bi << 5) | (al << 4))
        await tqv.write_reg(3, 5)
        assert (dut.uo_out.value & 0x1F) == u2 | (v2 << 1) | (w2 << 2) | (x2 << 3) | (y2 << 4)
        assert (await tqv.read_reg(4) & 0x1F) == u2 | (v2 << 1) | (w2 << 2) | (x2 << 3) | (y2 << 4)

    # Cistercian
    await test_cistercian(1, 1, 1, 1,  0, 15, 0,0,0,0,0, 0,1,1,1,1)
    await test_cistercian(1, 1, 1, 1,  2, 13, 0,1,0,0,0, 1,1,0,1,1)
    await test_cistercian(1, 1, 1, 1,  4, 11, 0,0,0,1,0, 1,0,0,1,1)
    await test_cistercian(1, 1, 1, 1,  6,  9, 0,0,0,0,1, 1,1,0,0,1)
    await test_cistercian(1, 1, 1, 1,  8,  7, 0,1,0,0,1, 1,0,0,0,1)
    await test_cistercian(1, 1, 1, 1, 10,  5, 1,1,1,1,0, 1,0,0,1,0)
    await test_cistercian(1, 1, 1, 1, 12,  3, 1,1,1,0,1, 0,0,1,0,0)
    await test_cistercian(1, 1, 1, 1, 14,  1, 1,0,1,1,1, 1,0,0,0,0)

    # Cistercian AL, BI, LT lines
    await test_cistercian(1, 1, 0, 1, 7, 7, 1,1,1,1,1, 1,0,0,0,1)
    await test_cistercian(1, 1, 1, 0, 7, 7, 1,0,0,0,1, 1,1,1,1,1)
    await test_cistercian(1, 1, 0, 0, 7, 7, 1,1,1,1,1, 1,1,1,1,1)
    await test_cistercian(1, 0, 0, 0, 7, 7, 0,0,0,0,0, 0,0,0,0,0)
    await test_cistercian(0, 0, 0, 0, 7, 7, 1,1,1,1,1, 1,1,1,1,1)

    async def test_kaktovik(rbi, bi, lt, al, vbi, value, data, rbo, v):
        await tqv.write_reg(0, value)
        await tqv.write_reg(1, (rbi << 7) | (lt << 6) | (bi << 5) | (al << 4))
        await tqv.write_reg(2, vbi)
        await tqv.write_reg(3, 6)
        assert dut.uo_out.value == data
        assert await tqv.read_reg(4) == data
        assert (await tqv.read_reg(5) & 0xF0) == (rbo << 7) | (v << 6)

    # Kaktovik
    await test_kaktovik(1, 1, 1, 1, 1,  0, 0b00000100, 1, 0)
    await test_kaktovik(1, 1, 1, 1, 1,  1, 0b00000001, 1, 0)
    await test_kaktovik(1, 1, 1, 1, 1, 19, 0b11111111, 1, 0)
    await test_kaktovik(1, 1, 1, 1, 1, 20, 0b11000000, 1, 1)
    await test_kaktovik(1, 1, 1, 1, 1, 30, 0b11111111, 1, 1)
    await test_kaktovik(1, 1, 1, 1, 1, 31, 0b00000000, 1, 1)

    # Kaktovik ripple blanking input
    await test_kaktovik(0, 1, 1, 1, 1,  0, 0b00000000, 0, 0)
    await test_kaktovik(0, 1, 1, 1, 1,  1, 0b00000001, 1, 0)
    await test_kaktovik(0, 1, 1, 1, 1, 19, 0b11111111, 1, 0)
    await test_kaktovik(0, 1, 1, 1, 1, 20, 0b11000000, 1, 1)
    await test_kaktovik(0, 1, 1, 1, 1, 30, 0b11111111, 1, 1)
    await test_kaktovik(0, 1, 1, 1, 1, 31, 0b00000000, 1, 1)

    # Kaktovik overflow blanking input
    await test_kaktovik(1, 1, 1, 1, 0,  0, 0b00000100, 1, 0)
    await test_kaktovik(1, 1, 1, 1, 0,  1, 0b00000001, 1, 0)
    await test_kaktovik(1, 1, 1, 1, 0, 19, 0b11111111, 1, 0)
    await test_kaktovik(1, 1, 1, 1, 0, 20, 0b00000000, 1, 1)
    await test_kaktovik(1, 1, 1, 1, 0, 30, 0b00000000, 1, 1)
    await test_kaktovik(1, 1, 1, 1, 0, 31, 0b00000000, 1, 1)

    # Kaktovik RBI, BI, LT, AT lines
    await test_kaktovik(0, 1, 1, 1, 1, 17, 0b11100111, 1, 0)
    await test_kaktovik(0, 1, 0, 1, 1, 17, 0b11111111, 1, 0)
    await test_kaktovik(0, 1, 0, 0, 1, 17, 0b00000000, 1, 0)
    await test_kaktovik(0, 0, 0, 0, 1, 17, 0b11111111, 0, 0)
    await test_kaktovik(1, 1, 1, 1, 1, 17, 0b11100111, 1, 0)
    await test_kaktovik(1, 1, 0, 1, 1, 17, 0b11111111, 1, 0)
    await test_kaktovik(1, 1, 0, 0, 1, 17, 0b00000000, 1, 0)
    await test_kaktovik(1, 0, 0, 0, 1, 17, 0b11111111, 0, 0)
