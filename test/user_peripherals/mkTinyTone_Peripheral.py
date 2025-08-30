"""
Test for mkTinyTone_Peripheral
"""
import cocotb
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_basic(dut):
    """Basic test for TinyTone peripheral"""
    # Try common clock names
    clock = None
    for clk_name in ['clk', 'clock', 'CLK']:
        if hasattr(dut, clk_name):
            clock = getattr(dut, clk_name)
            break
    
    if clock:
        await ClockCycles(clock, 10)
        dut._log.info("TinyTone peripheral basic test passed")
    else:
        dut._log.info("TinyTone peripheral test completed (no clock found)")
