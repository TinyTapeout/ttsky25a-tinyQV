import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
import struct
import math
import numpy as np
from tqv import TinyQV

PERIPHERAL_NUM = 32

def float_to_f16_hex(f):
    """Convert Python float to a 32-bit word with the lower 16 bits as IEEE-754 half-precision float."""
    f16 = np.float16(f)
    return int(f16.view(np.uint16))

def f16_hex_to_float(h16):
    """Convert 16-bit half-precision float stored in a 32-bit word to Python float."""
    return float(np.frombuffer(struct.pack('<H', h16 & 0xFFFF), dtype=np.float16)[0])

async def wait_until_not_busy(tqv, timeout=100):
    for _ in range(timeout):
        busy = await tqv.read_byte_reg(0x10)
        if busy == 0:
            return
        await ClockCycles(tqv.dut.clk, 1)
    raise TimeoutError("FPU remained busy after timeout")

@cocotb.test()
async def test_fpu_add(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())
    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    tests = [
        (1.5, 2.25),
        (100.0, 0.01),
        (-1.0, 1.),
        (-3.5, -2.5)
    ]

    for a, b in tests:
        await tqv.write_word_reg(0x00, float_to_f16_hex(a))  # operand_a
        await tqv.write_word_reg(0x01, float_to_f16_hex(b))  # operand_b

        await wait_until_not_busy(tqv)

        result = await tqv.read_word_reg(0x0C)
        actual = f16_hex_to_float(result)
        expected = float(np.float16(a) + np.float16(b))

        dut._log.info(f"ADD: {a} + {b} = {actual}, expected {expected}")
        assert abs(actual - expected) < 1e-2, f"ADD FAIL: {a} + {b} = {actual}, expected {expected}"

@cocotb.test()
async def test_fpu_sub(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())
    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    tests = [
        (5.0, 2.0, 3.0),
        (1.0, 2.0, -1.0),
        (-2.0, -2.0, 0.0),
    ]

    for a, b, expected in tests:
        await tqv.write_word_reg(0x04, float_to_f16_hex(a))
        await tqv.write_word_reg(0x05, float_to_f16_hex(b))

        await wait_until_not_busy(tqv)

        result = await tqv.read_word_reg(0x0C)
        actual = f16_hex_to_float(result)

        dut._log.info(f"SUB: {a} - {b} = {actual}, expected {expected}")
        assert abs(actual - expected) < 1e-2, f"SUB FAIL: {a} - {b} = {actual}, expected {expected}"

@cocotb.test()
async def test_fpu_mul(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())
    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    tests = [
        (2.0, 3.0, 6.0),
        (-1.5, 2.0, -3.0),
        (0.0, 100.0, 0.0),
        (5.5, 0.5, 2.75)
    ]

    for a, b, expected in tests:
        await tqv.write_word_reg(0x08, float_to_f16_hex(a))
        await tqv.write_word_reg(0x09, float_to_f16_hex(b))

        await wait_until_not_busy(tqv)

        result = await tqv.read_word_reg(0x0C)
        actual = f16_hex_to_float(result)

        dut._log.info(f"MUL: {a} * {b} = {actual}, expected {expected}")
        assert abs(actual - expected) < 1e-2, f"MUL FAIL: {a} * {b} = {actual}, expected {expected}"

@cocotb.test()
async def test_fpu_edge_cases(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())
    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    edge_tests = [
        (float('inf'), 1.0, float('inf'), 0x01, "INF + 1.0"),
        (float('-inf'), 1.0, float('-inf'), 0x01, "-INF + 1.0"),
        (float('inf'), float('-inf'), float('nan'), 0x01, "INF + -INF = NaN"),
        (float('nan'), 1.0, float('nan'), 0x01, "NaN + 1.0"),
        (0.0, -0.0, 0.0, 0x01, "+0.0 + -0.0"),
        #(65504.0, 65504.0, float('inf'), 0x01, "Overflow to INF"),  # TODO fix this test
        (1e-08, 1e-08, 2e-08, 0x01, "subnormal add"),
        (1e-08, -1e-08, 0.0, 0x01, "canceling subnormals"),
    ]

    for a, b, expected, control, desc in edge_tests:
        await tqv.write_word_reg(0x00, float_to_f16_hex(a))
        await tqv.write_word_reg(0x01, float_to_f16_hex(b))

        await wait_until_not_busy(tqv)

        result = await tqv.read_word_reg(0x0C)
        actual = f16_hex_to_float(result)

        # NaN handling (cannot compare equality directly)
        if math.isnan(expected):
            assert math.isnan(actual), f"EDGE FAIL: {desc} produced {actual}, expected NaN"
        elif math.isinf(expected):
            assert math.isinf(actual) and math.copysign(1.0, actual) == math.copysign(1.0, expected), \
                f"EDGE FAIL: {desc} produced {actual}, expected {expected}"
        else:
            assert abs(actual - expected) < 1e-2, f"EDGE FAIL: {desc} produced {actual}, expected {expected}"

        dut._log.info(f"EDGE: {desc} -> got {actual}, expected {expected}")
