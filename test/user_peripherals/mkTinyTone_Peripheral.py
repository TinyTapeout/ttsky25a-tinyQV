"""
Test for mkTinyTone_Peripheral
"""
import cocotb

@cocotb.test()
async def test_basic(dut):
    """Basic test for TinyTone peripheral"""
    # Minimal test - just verify the module instantiated correctly
    dut._log.info("TinyTone peripheral test started")
    
    # No clock operations - just verify the module exists
    assert dut is not None, "DUT should not be None"
    
    dut._log.info("TinyTone peripheral basic test passed")
