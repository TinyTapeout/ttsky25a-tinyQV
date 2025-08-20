# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

PERIPHERAL_NUM = 34

class MmReg:
    PROGRAM_HEADER    = 0x00
    PROGRAM_CODE      = 0x04
    AM_ADDRESS        = 0x08
    AM_FILE_DISCRIM   = 0x0C
    AM_LINE_COL_FLAGS = 0x10
    STATUS            = 0x14
    INFO              = 0x18

class StatusCode:
    READY    = 0
    EMIT_ROW = 1
    BUSY     = 2
    ILLEGAL  = 3

class StandardOpcode:
    DwLnsCopy             = 0x01
    DwLnsAdvancePc        = 0x02
    DwLnsAdvanceLine      = 0x03
    DwLnsSetFile          = 0x04
    DwLnsSetColumn        = 0x05
    DwLnsNegateStmt       = 0x06
    DwLnsSetBasicBlock    = 0x07
    DwLnsConstAddPc       = 0x08
    DwLnsFixedAdvancePc   = 0x09
    DwLnsSetPrologueEnd   = 0x0A
    DwLnsSetEpilogueBegin = 0x0B
    DwLnsSetIsa           = 0x0C

class ExtendedOpcode:
    START                 = 0x00
    DwLneEndSequence      = 0x01
    DwLneSetAddress       = 0x02
    DwLneSetDiscriminator = 0x04

@cocotb.test()
async def test_register_read_write_reset(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test default register values
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER)    == 0x0D010000
    assert await tqv.read_word_reg(MmReg.PROGRAM_CODE)      == 0x0
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS)        == 0x0
    assert await tqv.read_byte_reg(MmReg.AM_FILE_DISCRIM)   == 0x1
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x1
    assert await tqv.read_word_reg(MmReg.STATUS)            == StatusCode.READY
    assert await tqv.read_word_reg(MmReg.INFO)              == 0x00000155

    # test default value of is_stmt updated on new program header
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x0D010001)
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x4000001
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x0D010000)
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x1

    # test writes to read only registers are ignored
    await tqv.write_word_reg(MmReg.AM_ADDRESS, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    await tqv.write_word_reg(MmReg.AM_FILE_DISCRIM, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM) == 0x1
    await tqv.write_word_reg(MmReg.AM_LINE_COL_FLAGS, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x1
    await tqv.write_word_reg(MmReg.STATUS, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY
    await tqv.write_word_reg(MmReg.INFO, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.INFO) == 0x00000155

    # test writes to read-write registers
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0xABCD2301)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0xABCD2301

    # test writes to write-only registers
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.PROGRAM_CODE) == 0x0

    # test writes to read only regions of writable registers are ignored
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0xFFFFFFFF)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0xFFFFFF01

    # test write illegal line range to program header
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x0)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0x00010000

    # test accesses to non-existent registers do nothing
    real_registers = set([
        MmReg.PROGRAM_HEADER,
        MmReg.PROGRAM_CODE,
        MmReg.AM_ADDRESS,
        MmReg.AM_FILE_DISCRIM,
        MmReg.AM_LINE_COL_FLAGS,
        MmReg.STATUS,
        MmReg.INFO,
    ])
    for illegal_reg in [i for i in range(64) if i not in real_registers]:
        await tqv.write_word_reg(illegal_reg, 0xFFFFFFFF)
        assert await tqv.read_word_reg(illegal_reg) == 0x0

@cocotb.test()
async def test_partial_program_header_access(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test write each byte of program header individually
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0x0D010000
    await tqv.write_byte_reg(MmReg.PROGRAM_HEADER + 3, 0xAB)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0xAB010000
    await tqv.write_byte_reg(MmReg.PROGRAM_HEADER + 2, 0x00)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0xAB010000
    await tqv.write_byte_reg(MmReg.PROGRAM_HEADER + 1, 0xCD)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0xAB01CD00
    await tqv.write_byte_reg(MmReg.PROGRAM_HEADER, 0x0F)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0xAB01CD01

    # test write each nibble of the program header individually
    await tqv.write_hword_reg(MmReg.PROGRAM_HEADER + 2, 0x3344)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0x3344CD01
    await tqv.write_hword_reg(MmReg.PROGRAM_HEADER, 0x5566)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0x33445500

    # test misaligned word writes of program header are ignored
    for i in [1, 2, 3]:
        await tqv.write_word_reg(MmReg.PROGRAM_HEADER + i, 0x11111111)
        assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0x33445500

    # test misaligned nibble writes of program header are ignored
    for i in [1, 3]:
        await tqv.write_hword_reg(MmReg.PROGRAM_HEADER + i, 0x1111)
        assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0x33445500

    # test read each byte of the program header individually
    assert await tqv.read_byte_reg(MmReg.PROGRAM_HEADER) == 0x00
    assert await tqv.read_byte_reg(MmReg.PROGRAM_HEADER + 1) == 0x55
    assert await tqv.read_byte_reg(MmReg.PROGRAM_HEADER + 2) == 0x44
    assert await tqv.read_byte_reg(MmReg.PROGRAM_HEADER + 3) == 0x33

    # test read each nibble of the program header individually
    assert await tqv.read_hword_reg(MmReg.PROGRAM_HEADER) == 0x5500
    assert await tqv.read_hword_reg(MmReg.PROGRAM_HEADER + 2) == 0x3344

    # test misaligned word reads of program header return 0
    for i in [1, 2, 3]:
        assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER + i) == 0x0

    # test misaligned nibble reads of program header return 0
    for i in [1, 3]:
        assert await tqv.read_hword_reg(MmReg.PROGRAM_HEADER + i) == 0x0

@cocotb.test()
async def test_partial_program_code_access(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test byte aligned writes to program code all behave the same
    for i in [0, 1, 2, 3]:
        await tqv.write_byte_reg(MmReg.PROGRAM_CODE + i, StandardOpcode.DwLnsCopy)
        assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
        await tqv.write_word_reg(MmReg.STATUS, 0)

    # test nibble aligned writes to program code all behave the same
    for i in [0, 2]:
        await tqv.write_hword_reg(MmReg.PROGRAM_CODE + i, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetBasicBlock)
        assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
        assert await read_am_basic_block(tqv) == 1
        await tqv.write_word_reg(MmReg.STATUS, 0)

    # test misaligned word writes to program code are ignored
    await tqv.write_word_reg(MmReg.PROGRAM_CODE + 1, (StandardOpcode.DwLnsCopy << 16) | (StandardOpcode.DwLnsSetBasicBlock << 8) | StandardOpcode.DwLnsSetBasicBlock)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY
    assert await read_am_basic_block(tqv)        == 0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE + 2, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetBasicBlock)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY
    assert await read_am_basic_block(tqv)        == 0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE + 3, StandardOpcode.DwLnsCopy)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY

    # test misaligned nibble writes to program code are ignored
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE + 1, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetBasicBlock)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY
    assert await read_am_basic_block(tqv)        == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE + 3, StandardOpcode.DwLnsCopy)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY

    # test all reads from program code return 0
    for i in range(4):
        assert await tqv.read_byte_reg(MmReg.PROGRAM_CODE + i)  == 0x0
        assert await tqv.read_hword_reg(MmReg.PROGRAM_CODE + i) == 0x0
        assert await tqv.read_word_reg(MmReg.PROGRAM_CODE + i)  == 0x0

@cocotb.test()
async def test_partial_am_address_access(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xF3A2A3 << 8) | StandardOpcode.DwLnsAdvancePc)
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | 0x55)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0xABCD123

    # test read each byte of the address individually
    assert await tqv.read_byte_reg(MmReg.AM_ADDRESS)     == 0x23
    assert await tqv.read_byte_reg(MmReg.AM_ADDRESS + 1) == 0xD1
    assert await tqv.read_byte_reg(MmReg.AM_ADDRESS + 2) == 0xBC
    assert await tqv.read_byte_reg(MmReg.AM_ADDRESS + 3) == 0x0A

    # test read each nibble of the address individually
    assert await tqv.read_hword_reg(MmReg.AM_ADDRESS)     == 0xD123
    assert await tqv.read_hword_reg(MmReg.AM_ADDRESS + 2) == 0x0ABC

    # test misaligned word reads of address return 0
    for i in [1, 2, 3]:
        assert await tqv.read_word_reg(MmReg.AM_ADDRESS + i) == 0x0

    # test misaligned nibble reads of address return 0
    for i in [1, 3]:
        assert await tqv.read_hword_reg(MmReg.AM_ADDRESS + i) == 0x0

    # test all writes to address are ignored
    for i in range(4):
        await tqv.write_byte_reg(MmReg.AM_ADDRESS + i, 0x11)
        assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0xABCD123
        await tqv.write_hword_reg(MmReg.AM_ADDRESS + i, 0x1111)
        assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0xABCD123
        await tqv.write_word_reg(MmReg.AM_ADDRESS + i, 0x11111111)
        assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0xABCD123

@cocotb.test()
async def test_partial_am_file_discrim_access(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    assert await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM) == 0x1
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x2D7CD << 8) | StandardOpcode.DwLnsSetFile)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xB4 << 24) | (ExtendedOpcode.DwLneSetDiscriminator << 16) | (0x04 << 8) | ExtendedOpcode.START)
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | 0x24)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM) == 0x1234ABCD

    # test read each byte of file/discrim individually
    assert await tqv.read_byte_reg(MmReg.AM_FILE_DISCRIM)     == 0xCD
    assert await tqv.read_byte_reg(MmReg.AM_FILE_DISCRIM + 1) == 0xAB
    assert await tqv.read_byte_reg(MmReg.AM_FILE_DISCRIM + 2) == 0x34
    assert await tqv.read_byte_reg(MmReg.AM_FILE_DISCRIM + 3) == 0x12

    # test read each nibble of file/discrim individually
    assert await tqv.read_hword_reg(MmReg.AM_FILE_DISCRIM)     == 0xABCD
    assert await tqv.read_hword_reg(MmReg.AM_FILE_DISCRIM + 2) == 0x1234

    # test misaligned word reads of file/discrim return 0
    for i in [1, 2, 3]:
        assert await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM + i) == 0x0

    # test misaligned nibble reads of file/discrim return 0
    for i in [1, 3]:
        assert await tqv.read_hword_reg(MmReg.AM_FILE_DISCRIM + i) == 0x0

    # test all writes to file/discrim are ignored
    for i in range(4):
        await tqv.write_byte_reg(MmReg.AM_FILE_DISCRIM + i, 0x11)
        assert await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM) == 0x1234ABCD
        await tqv.write_hword_reg(MmReg.AM_FILE_DISCRIM + i, 0x1111)
        assert await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM) == 0x1234ABCD
        await tqv.write_word_reg(MmReg.AM_FILE_DISCRIM + i, 0x11111111)
        assert await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM) == 0x1234ABCD

@cocotb.test()
async def test_partial_am_line_col_flags_access(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x1
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsSetColumn << 24) | (0x24B4 << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (StandardOpcode.DwLnsSetPrologueEnd << 16) | 0x06B3)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x23331235

    # test read each byte of line/col/flags individually
    assert await tqv.read_byte_reg(MmReg.AM_LINE_COL_FLAGS)     == 0x35
    assert await tqv.read_byte_reg(MmReg.AM_LINE_COL_FLAGS + 1) == 0x12
    assert await tqv.read_byte_reg(MmReg.AM_LINE_COL_FLAGS + 2) == 0x33
    assert await tqv.read_byte_reg(MmReg.AM_LINE_COL_FLAGS + 3) == 0x23

    # test read each nibble of line/col/flags individually
    assert await tqv.read_hword_reg(MmReg.AM_LINE_COL_FLAGS)     == 0x1235
    assert await tqv.read_hword_reg(MmReg.AM_LINE_COL_FLAGS + 2) == 0x2333

    # test misaligned word reads of line/col/flags return 0
    for i in [1, 2, 3]:
        assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS + i) == 0x0

    # test misaligned nibble reads of line/col/flags return 0
    for i in [1, 3]:
        assert await tqv.read_hword_reg(MmReg.AM_LINE_COL_FLAGS + i) == 0x0

    # test all writes to line/col/flags are ignored
    for i in range(4):
        await tqv.write_byte_reg(MmReg.AM_LINE_COL_FLAGS + i, 0x11)
        assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x23331235
        await tqv.write_hword_reg(MmReg.AM_LINE_COL_FLAGS + i, 0x1111)
        assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x23331235
        await tqv.write_word_reg(MmReg.AM_LINE_COL_FLAGS + i, 0x11111111)
        assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x23331235

@cocotb.test()
async def test_partial_status_access(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.EMIT_ROW

    # test read each byte of status individually
    assert await tqv.read_byte_reg(MmReg.STATUS)     == StatusCode.EMIT_ROW
    assert await tqv.read_byte_reg(MmReg.STATUS + 1) == 0x00
    assert await tqv.read_byte_reg(MmReg.STATUS + 2) == 0x00
    assert await tqv.read_byte_reg(MmReg.STATUS + 3) == 0x00

    # test read each nibble of status individually
    assert await tqv.read_hword_reg(MmReg.STATUS)     == StatusCode.EMIT_ROW
    assert await tqv.read_hword_reg(MmReg.STATUS + 2) == 0x0000

    # test misaligned word reads of status return 0
    for i in [1, 2, 3]:
        assert await tqv.read_word_reg(MmReg.STATUS + i) == 0x0

    # test misaligned nibble reads of status return 0
    for i in [1, 3]:
        assert await tqv.read_hword_reg(MmReg.STATUS + i) == 0x0

    # test misaligned word writes to status are ignored
    for i in [1, 2, 3]:
        await tqv.write_word_reg(MmReg.STATUS + i, 0)
        assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.EMIT_ROW

    # test misaligned nibble writes to status are ignored
    for i in [1, 3]:
        await tqv.write_hword_reg(MmReg.STATUS + i, 0)
        assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.EMIT_ROW

    # test aligned word write to status is accepted
    await tqv.write_word_reg(MmReg.STATUS, 0)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY

    # test all byte writes to status are accepted
    for i in range(4):
        await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
        assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.EMIT_ROW
        await tqv.write_byte_reg(MmReg.STATUS, i)
        assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY

    # test all aligned nibble writes to status are accepted
    for i in [0, 2]:
        await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
        assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.EMIT_ROW
        await tqv.write_hword_reg(MmReg.STATUS, i)
        assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY

@cocotb.test()
async def test_partial_info_access(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    assert await tqv.read_word_reg(MmReg.INFO) == 0x00000155

    # test read each byte of info individually
    assert await tqv.read_byte_reg(MmReg.INFO)     == 0x55
    assert await tqv.read_byte_reg(MmReg.INFO + 1) == 0x01
    assert await tqv.read_byte_reg(MmReg.INFO + 2) == 0x00
    assert await tqv.read_byte_reg(MmReg.INFO + 3) == 0x00

    # test read each nibble of info individually
    assert await tqv.read_hword_reg(MmReg.INFO)     == 0x0155
    assert await tqv.read_hword_reg(MmReg.INFO + 2) == 0x0000

    # test misaligned word reads of info return 0
    for i in [1, 2, 3]:
        assert await tqv.read_word_reg(MmReg.INFO + i) == 0x0

    # test misaligned nibble reads of info return 0
    for i in [1, 3]:
        assert await tqv.read_hword_reg(MmReg.INFO + i) == 0x0

    # test all writes to info are ignored
    for i in range(4):
        await tqv.write_byte_reg(MmReg.INFO + i, 0x11)
        assert await tqv.read_word_reg(MmReg.INFO) == 0x00000155
        await tqv.write_hword_reg(MmReg.INFO + i, 0x1111)
        assert await tqv.read_word_reg(MmReg.INFO) == 0x00000155
        await tqv.write_word_reg(MmReg.INFO + i, 0x11111111)
        assert await tqv.read_word_reg(MmReg.INFO) == 0x00000155

@cocotb.test()
async def test_dw_lns_copy(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test copy instruction emits row via status code
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS)        == 0x0
    assert await tqv.read_byte_reg(MmReg.AM_FILE_DISCRIM)   == 0x1
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x1

    # test clear status register
    await tqv.write_word_reg(MmReg.STATUS, 0)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY

    # test two copy instructions in a row
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    await tqv.write_hword_reg(MmReg.STATUS, 1)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    await tqv.write_byte_reg(MmReg.STATUS, 254)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY

@cocotb.test()
async def test_dw_lns_advance_pc(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test advance pc with one byte operand
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (4 << 8) | StandardOpcode.DwLnsAdvancePc)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x4
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with two byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x7494 << 8) | StandardOpcode.DwLnsAdvancePc)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x3A18
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with three byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x018182 << 8) | StandardOpcode.DwLnsAdvancePc)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x7A9A
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with four byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x8392A4 << 8) | StandardOpcode.DwLnsAdvancePc)
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | 0x04)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x8143BE
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with odd operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x0183 << 8) | StandardOpcode.DwLnsAdvancePc)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x814441
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with overflowing operand
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsAdvancePc)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0x80808082)
    for i in range(10):
        await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0xFFFFFFFF)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0x01808080)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x814443
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test overflow of address register
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xFFFFFF << 8) | StandardOpcode.DwLnsAdvancePc)
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | 0x7F)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x814442
    await tqv.write_word_reg(MmReg.STATUS, 0)

@cocotb.test()
async def test_dw_lns_advance_line(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test advance line with one byte positive operand
    assert await read_am_line(tqv) == 0x1
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (2 << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_line(tqv) == 0x3
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with one byte negative operand
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x7F << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_line(tqv) == 0x2
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with two byte positive operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x1298 << 8) | StandardOpcode.DwLnsAdvanceLine)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_line(tqv) == 0x91A
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with two byte negative operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x6DE8 << 8) | StandardOpcode.DwLnsAdvanceLine)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_line(tqv) == 0x2
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with three byte positive operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x039298 << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_line(tqv) == 0xC91A
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with three byte negative operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x7CEDE8 << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_line(tqv) == 0x2
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test underflow of line register
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x7B << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_line(tqv) == 0xFFFD
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test overflow of line register
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x05 << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_line(tqv) == 0x2
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_file(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set file with one byte operand
    assert await read_am_file(tqv) == 0x1
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x05 << 8) | StandardOpcode.DwLnsSetFile)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_file(tqv) == 0x5
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test set file with two byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x0185 << 8) | StandardOpcode.DwLnsSetFile)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_file(tqv) == 0x85
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test set file with three byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x03A2B1 << 8) | StandardOpcode.DwLnsSetFile)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_file(tqv) == 0xD131
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test overflow file register
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x07B3C4 << 8) | StandardOpcode.DwLnsSetFile)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_file(tqv) == 0xD9C4
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_column(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set column with one byte operand
    assert await read_am_column(tqv) == 0x0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x05 << 8) | StandardOpcode.DwLnsSetColumn)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_column(tqv) == 0x5
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test set column with two byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x0185 << 8) | StandardOpcode.DwLnsSetColumn)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_column(tqv) == 0x85
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test overflow column register
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x03A2B1 << 8) | StandardOpcode.DwLnsSetColumn)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_column(tqv) == 0x131
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_negate_stmt(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test flip from 0 to 1
    assert await read_am_is_stmt(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsNegateStmt)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_is_stmt(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test flip from 1 to 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsNegateStmt)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_is_stmt(tqv) == 0
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test two back to back flips
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsNegateStmt << 8) | StandardOpcode.DwLnsNegateStmt)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_is_stmt(tqv) == 0
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test three back to back flips
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (StandardOpcode.DwLnsNegateStmt << 16) | (StandardOpcode.DwLnsNegateStmt << 8) | StandardOpcode.DwLnsNegateStmt)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_is_stmt(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_basic_block(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test setting basic block
    assert await read_am_basic_block(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetBasicBlock)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_basic_block(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after copy reset basic block
    assert await read_am_basic_block(tqv) == 0

    # test setting basic block twice back to back
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsSetBasicBlock << 8) | StandardOpcode.DwLnsSetBasicBlock)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_basic_block(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_const_add_pc(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test const add pc with line_base=-3 and line_range=7
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x0D07FD00)
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsConstAddPc)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 100)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 34
    assert await read_am_line(tqv)                   == 1
    await tqv.write_byte_reg(MmReg.STATUS, 0)

    # test multiple const add pc with line_base=-4 and line_range=25
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x0D19FC00)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (StandardOpcode.DwLnsConstAddPc << 16) | (StandardOpcode.DwLnsConstAddPc << 8) | StandardOpcode.DwLnsConstAddPc)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 100)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 27
    assert await read_am_line(tqv)                   == 1
    await tqv.write_byte_reg(MmReg.STATUS, 0)

@cocotb.test()
async def test_dw_lns_fixed_advance_pc(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test fixed advance pc
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x1234 << 8) | StandardOpcode.DwLnsFixedAdvancePc)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x1234
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test fixed advance pc with odd operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0xABCD << 8) | StandardOpcode.DwLnsFixedAdvancePc)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0xBE01
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_prologue_end(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set prologue end
    assert await read_am_prologue_end(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetPrologueEnd)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_prologue_end(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after copy reset prologue end
    assert await read_am_prologue_end(tqv) == 0

    # test set prologue end twice back to back
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsSetPrologueEnd << 8) | StandardOpcode.DwLnsSetPrologueEnd)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_prologue_end(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_epilogue_begin(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set epilogue begin
    assert await read_am_epilogue_begin(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetEpilogueBegin)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_epilogue_begin(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after copy reset epilogue begin
    assert await read_am_epilogue_begin(tqv) == 0

    # test set epilogue begin twice back to back
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsSetEpilogueBegin << 8) | StandardOpcode.DwLnsSetEpilogueBegin)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_epilogue_begin(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_isa(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set isa with single byte operand is correctly parsed as a nop
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x01 << 8) | StandardOpcode.DwLnsSetIsa)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test set isa with multi byte operand is correctly parsed as a nop
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xFFFFFF << 8) | StandardOpcode.DwLnsSetIsa)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0xFFFFFFFF)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | 0x7FFFFF)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lne_end_sequence(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test end sequence sets end sequence flag
    assert await read_am_end_sequence(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x01 << 8) | ExtendedOpcode.START)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, ExtendedOpcode.DwLneEndSequence)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_end_sequence(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after end sequence reset end sequence flag
    assert await read_am_epilogue_begin(tqv) == 0

    # test end sequence resets entire state machine after restart
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x0D010001)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    assert await read_am_file(tqv)           == 1
    assert await read_am_line(tqv)           == 1
    assert await read_am_column(tqv)         == 0
    assert await read_am_is_stmt(tqv)        == 1
    assert await read_am_basic_block(tqv)    == 0
    assert await read_am_end_sequence(tqv)   == 0
    assert await read_am_prologue_end(tqv)   == 0
    assert await read_am_epilogue_begin(tqv) == 0
    assert await read_am_discrim(tqv)        == 0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x04 << 24) | (StandardOpcode.DwLnsAdvanceLine << 16) | (0x0A << 8) | StandardOpcode.DwLnsSetFile)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsSetBasicBlock << 24) | (StandardOpcode.DwLnsNegateStmt << 16) | (0x0B << 8) | StandardOpcode.DwLnsSetColumn)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x02 << 24) | (ExtendedOpcode.START << 16) | (StandardOpcode.DwLnsSetEpilogueBegin << 8) | StandardOpcode.DwLnsSetPrologueEnd)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x01 << 24) | (ExtendedOpcode.START << 16) | (0x06 << 8) | ExtendedOpcode.DwLneSetDiscriminator)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, ExtendedOpcode.DwLneEndSequence)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_file(tqv)           == 10
    assert await read_am_line(tqv)           == 5
    assert await read_am_column(tqv)         == 11
    assert await read_am_is_stmt(tqv)        == 0
    assert await read_am_basic_block(tqv)    == 1
    assert await read_am_end_sequence(tqv)   == 1
    assert await read_am_prologue_end(tqv)   == 1
    assert await read_am_epilogue_begin(tqv) == 1
    assert await read_am_discrim(tqv)        == 6
    await tqv.write_byte_reg(MmReg.STATUS, 1)
    assert await read_am_file(tqv)           == 1
    assert await read_am_line(tqv)           == 1
    assert await read_am_column(tqv)         == 0
    assert await read_am_is_stmt(tqv)        == 1
    assert await read_am_basic_block(tqv)    == 0
    assert await read_am_end_sequence(tqv)   == 0
    assert await read_am_prologue_end(tqv)   == 0
    assert await read_am_epilogue_begin(tqv) == 0
    assert await read_am_discrim(tqv)        == 0

@cocotb.test()
async def test_dw_lne_set_address(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set address
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xDD << 24) | (ExtendedOpcode.DwLneSetAddress << 16) | (0x05 << 8) | ExtendedOpcode.START)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | 0xAABBCC)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0xABBCCDD
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lne_set_discriminator(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set discriminator
    assert await read_am_discrim(tqv) == 0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x05 << 24) | (ExtendedOpcode.DwLneSetDiscriminator << 16) | (0x02 << 8) | ExtendedOpcode.START)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_discrim(tqv) == 5
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after copy reset discriminator register
    assert await read_am_discrim(tqv) == 0

    # test overflow discriminator register
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xFF << 24) | (ExtendedOpcode.DwLneSetDiscriminator << 16) | (0x05 << 8) | ExtendedOpcode.START)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | 0x7FFFFF)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_discrim(tqv) == 0xFFFF
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_special_opcodes(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test interesting combinations of opcode_base, line_base, line_range, and opcode
    for opcode_base in [0, 1, 13, 255]:
        for line_base in [0, 1, 127, -1, -128]:
            for line_range in [1, 7, 255]:
                step_size = max(1, (256 - opcode_base) // 3)
                opcodes   = list(range(opcode_base, 256, step_size))
                if 255 not in opcodes:
                    opcodes += [255]
                for opcode in opcodes:
                    await run_special_opcode_test(dut, tqv, opcode_base, line_base, line_range, opcode)

    # test that basic_block, prologue_end, epilogue_begin, and discriminator are reset by special opcode
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x0D0A0200)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (ExtendedOpcode.START << 24) | (StandardOpcode.DwLnsSetEpilogueBegin << 16) | (StandardOpcode.DwLnsSetPrologueEnd << 8) | StandardOpcode.DwLnsSetBasicBlock)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xDC << 24) | (0x02 << 16) | (ExtendedOpcode.DwLneSetDiscriminator << 8) | 0x02)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 100)
    assert await read_am_basic_block(tqv)    == 1
    assert await read_am_prologue_end(tqv)   == 1
    assert await read_am_epilogue_begin(tqv) == 1
    assert await read_am_discrim(tqv)        == 2
    await tqv.write_byte_reg(MmReg.STATUS, 0)
    assert await read_am_basic_block(tqv)    == 0
    assert await read_am_prologue_end(tqv)   == 0
    assert await read_am_epilogue_begin(tqv) == 0
    assert await read_am_discrim(tqv)        == 0

async def run_special_opcode_test(dut, tqv, opcode_base, line_base, line_range, opcode):
    adjusted_opcode  = opcode - opcode_base
    expected_address = adjusted_opcode // line_range
    expected_line    = (line_base + (adjusted_opcode % line_range) + 1) & 0xFFFF
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, (opcode_base << 24) | (line_range << 16) | ((line_base & 0xFF) << 8))
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, opcode)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 100)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == expected_address
    assert await read_am_line(tqv)                   == expected_line
    await tqv.write_byte_reg(MmReg.STATUS, 0)

@cocotb.test()
async def test_illegal_instruction(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test illegal extended opcodes
    for illegal_opcode in [0x3, 0x66]:
        await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x09 << 8) | ExtendedOpcode.START)
        await tqv.write_byte_reg(MmReg.PROGRAM_CODE, illegal_opcode)
        assert await wait_for_status_code(dut, tqv, StatusCode.ILLEGAL, 10)
        assert await read_am_basic_block(tqv) == 0
        await tqv.write_byte_reg(MmReg.STATUS, 0)
        assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY

    # test valid code runs correctly after illegal
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetBasicBlock)
    assert await wait_for_status_code(dut, tqv, StatusCode.EMIT_ROW, 10)
    assert await read_am_basic_block(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 0)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY
    assert await read_am_basic_block(tqv)        == 0

    # test illegal standard opcodes
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x0F010000)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, 0x0E)
    assert await wait_for_status_code(dut, tqv, StatusCode.ILLEGAL, 10)
    assert await read_am_basic_block(tqv) == 0
    await tqv.write_byte_reg(MmReg.STATUS, 0)
    assert await tqv.read_word_reg(MmReg.STATUS) == StatusCode.READY

async def wait_for_status_code(dut, tqv, status_code, timeout):
    while timeout > 0:
        await ClockCycles(dut.clk, 1)
        current_status_code = await tqv.read_byte_reg(MmReg.STATUS)
        assert current_status_code != StatusCode.READY
        if current_status_code == status_code:
            return True
        else:
            timeout -= 1
    return False

async def read_am_line(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return line_col_flags & 0xFFFF

async def read_am_column(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 16) & 0x3FF

async def read_am_is_stmt(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 26) & 1

async def read_am_basic_block(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 27) & 1

async def read_am_end_sequence(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 28) & 1

async def read_am_prologue_end(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 29) & 1

async def read_am_epilogue_begin(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 30) & 1

async def read_am_file(tqv):
    file_descrim = await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM)
    return file_descrim & 0xFFFF

async def read_am_discrim(tqv):
    file_descrim = await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM)
    return (file_descrim >> 16) & 0xFFFF
