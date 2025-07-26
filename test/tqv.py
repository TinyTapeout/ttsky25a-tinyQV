from cocotb.triggers import ClockCycles

from riscvmodel.insn import *
from riscvmodel.regnames import x0, tp, a0, a1
from riscvmodel import csrnames

import test_util

# This class provides access to the peripheral's registers.
class TinyQV:

    # The peripheral number must be provided.
    def __init__(self, dut, peripheral_num):
        self.dut = dut
        self.peripheral_num = peripheral_num
        if peripheral_num < 16:
            self.base_address = peripheral_num * 0x40
        else:
            self.base_address = 0x300 + peripheral_num * 0x10

    # Reset the design, this reset will initialize TinyQV and connect
    # all inputs and outputs to your peripheral.
    async def reset(self, initial_ui_in=0):
        await test_util.reset(self.dut, 1, initial_ui_in)

        # Should start reading flash after 1 cycle
        await ClockCycles(self.dut.clk, 1)
        await test_util.start_read(self.dut, 0)
        
        await test_util.set_all_outputs_to_peripheral(self.dut, self.peripheral_num)

        test_util.start_nops(self.dut)

    # Write a value to a byte register in your design
    # reg is the address of the register in the range 0-15
    # value is the value to be written, in the range 0-255
    # If sync is false this function will return before the store is completed.
    async def write_reg(self, reg, value, sync=True):
        await test_util.stop_nops()
        await test_util.send_instr(self.dut, InstructionADDI(a1, x0, value).encode())
        await test_util.send_instr(self.dut, InstructionSB(tp, a1, self.base_address + reg).encode())

        if sync:
            # Read a register in order to ensure the store is complete before returning
            assert await test_util.read_reg(self.dut, a1) == value

        test_util.start_nops(self.dut)

    # Read the value of a byte register from your design
    # reg is the address of the register in the range 0-15
    # The returned value is the data read from the register, in the range 0-255
    async def read_reg(self, reg):
        await test_util.stop_nops()
        await test_util.send_instr(self.dut, InstructionLBU(a1, tp, self.base_address + reg).encode())
        val = await test_util.read_reg(self.dut, a1)
        test_util.start_nops(self.dut)
        return val

    # Write a value to a byte register in your design
    # reg is the address of the register in the range 0-15
    # value is the value to be written, in the range 0-255
    # If sync is false this function will return before the store is completed.
    async def write_byte_reg(self, reg, value, sync=True):
        await self.write_reg(reg, value, sync)

    # Read the value of a byte register from your design
    # reg is the address of the register in the range 0-15
    # The returned value is the data read from the register, in the range 0-255
    async def read_byte_reg(self, reg):
        return await self.read_reg(reg)

    # Write a value to a half word register in your design
    # reg is the address of the register in the range 0-15
    # value is the value to be written, in the range 0-65535
    # If sync is false this function will return before the store is completed.
    async def write_hword_reg(self, reg, value, sync=True):
        await test_util.stop_nops()
        # Prepare value for LUI + ADDI
        value_upper = (value + 0x800) >> 12
        value_lower = value & 0xfff
        if value_lower >= 0x800:
            value_lower -= 0x1000

        await test_util.send_instr(self.dut, InstructionLUI(a1, value_upper).encode())
        await test_util.send_instr(self.dut, InstructionADDI(a1, a1, value_lower).encode())
        await test_util.send_instr(self.dut, InstructionSH(tp, a1, self.base_address + reg).encode())

        if sync:
            # Read a register in order to ensure the store is complete before returning
            assert await test_util.read_reg(self.dut, a1) == value

        test_util.start_nops(self.dut)

    # Read the value of a half word register from your design
    # reg is the address of the register in the range 0-15
    # The returned value is the data read from the register, in the range 0-65535
    async def read_hword_reg(self, reg):
        await test_util.stop_nops()
        await test_util.send_instr(self.dut, InstructionLHU(a1, tp, self.base_address + reg).encode())
        val = await test_util.read_reg(self.dut, a1)
        test_util.start_nops(self.dut)
        return val

    # Write a value to a word register in your design
    # reg is the address of the register in the range 0-15
    # value is the value to be written
    # If sync is false this function will return before the store is completed.
    async def write_word_reg(self, reg, value, sync=True):
        await test_util.stop_nops()

        # Prepare value for LUI + ADDI
        value_upper = (value + 0x800) >> 12
        value_lower = value & 0xfff
        if value_lower >= 0x800:
            value_lower -= 0x1000

        await test_util.send_instr(self.dut, InstructionLUI(a1, value_upper).encode())
        await test_util.send_instr(self.dut, InstructionADDI(a1, a1, value_lower).encode())
        await test_util.send_instr(self.dut, InstructionSW(tp, a1, self.base_address + reg).encode())

        if sync:
            # Read a register in order to ensure the store is complete before returning
            assert await test_util.read_reg(self.dut, a1) == value

        test_util.start_nops(self.dut)

    # Read the value of a word register from your design
    # reg is the address of the register in the range 0-15
    # The returned value is the data read from the register
    async def read_word_reg(self, reg):
        await test_util.stop_nops()
        await test_util.send_instr(self.dut, InstructionLW(a1, tp, self.base_address + reg).encode())
        val = await test_util.read_reg(self.dut, a1)
        test_util.start_nops(self.dut)
        return val

    # Check whether the user interrupt is asserted
    async def is_interrupt_asserted(self):
        await test_util.stop_nops()
        await test_util.send_instr(self.dut, InstructionCSRRS(a1, x0, csrnames.mip).encode())
        val = await test_util.read_reg(self.dut, a1)
        test_util.start_nops(self.dut)
        return (val & (1 << (16 + self.peripheral_num))) != 0
