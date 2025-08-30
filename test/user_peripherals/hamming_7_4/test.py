# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

PERIPHERAL_NUM = 31

async def setup_test(dut):
    """Common setup for all tests"""
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())
    
    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()
    
    return tqv

@cocotb.test()
async def test_encoder_basic(dut):
    """Test basic encoding functionality"""
    tqv = await setup_test(dut)
    dut._log.info("Testing basic Hamming encoder functionality")
    
    # Test Hamming(7,4) encoding
    test_data = 0xD
    await tqv.write_reg(0, test_data)
    await ClockCycles(dut.clk, 2)
    
    encoded = await tqv.read_reg(1)
    expected_encoded = 0x66
    assert encoded == expected_encoded, f"Test 1: Expected {expected_encoded:02x}, got {encoded:02x}"
    
    test_data = 0xA
    await tqv.write_reg(0, test_data)
    await ClockCycles(dut.clk, 2)
    
    encoded = await tqv.read_reg(1)
    expected_encoded = 0x52
    assert encoded == expected_encoded, f"Test 2: Expected {expected_encoded:02x}, got {encoded:02x}"
    
    test_data = 0x0
    await tqv.write_reg(0, test_data)
    await ClockCycles(dut.clk, 2)
    
    encoded = await tqv.read_reg(1)
    expected_encoded = 0x00
    assert encoded == expected_encoded, f"Test 3: Expected {expected_encoded:02x}, got {encoded:02x}"
    
    dut._log.info("Basic encoder tests passed!")

@cocotb.test()
async def test_decoder_no_errors(dut):
    """Test decoder with error-free data"""
    tqv = await setup_test(dut)
    dut._log.info("Testing Hamming decoder with no errors")
    
    # Valid Hamming(7,4) code pairs
    test_cases = [
        (0xD, 0x66),  
        (0xA, 0x52), 
        (0x7, 0x34),   
        (0x0, 0x00)   
    ]
    
    for original_data, expected_encoded in test_cases:
        # Encode data
        await tqv.write_reg(0, original_data)
        await ClockCycles(dut.clk, 3)
        
        # Verify encoding (bits [6:0], bit 7 is always 0)
        encoded_read = await tqv.read_reg(1)
        actual_encoded = encoded_read & 0x7F
        
        assert actual_encoded == expected_encoded, \
            f"Encoding failed for {original_data:02x}: expected {expected_encoded:02x}, got {actual_encoded:02x}"
        
        # Decode the encoded data
        await tqv.write_reg(3, encoded_read)
        await ClockCycles(dut.clk, 3)
        
        # Verify decoding (bits [3:0], upper bits are 0)
        decoded = await tqv.read_reg(3)
        actual_decoded = decoded & 0x0F
        
        assert actual_decoded == original_data, \
            f"Decoding failed for {expected_encoded:02x}: expected {original_data:02x}, got {actual_decoded:02x}"
        
        # Verify no error detected (syndrome = 0)
        syndrome = await tqv.read_reg(4)
        assert syndrome == 0, f"Syndrome should be 0, got {syndrome:02x}"
    
    dut._log.info("Decoder no-error tests passed!")
    
@cocotb.test()
async def test_decoder_single_bit_errors(dut):
    """Test decoder with single-bit errors"""
    tqv = await setup_test(dut)
    dut._log.info("Testing Hamming decoder with single-bit errors")
    
    original_data = 0xD
    encoded_data = 0x66  # Correct Hamming(7,4) encoding of 0xD
    
    # Test error correction for each bit position
    for error_bit in range(7):
        # Create corrupted data by flipping one bit
        corrupted = encoded_data ^ (1 << error_bit)
        
        # Feed corrupted data to decoder
        await tqv.write_reg(3, corrupted)
        await ClockCycles(dut.clk, 2)
        
        # Verify error correction
        decoded = await tqv.read_reg(3)
        assert decoded == original_data, f"Error correction failed for bit {error_bit}. Got {decoded:02x}, expected {original_data:02x}"
        
        # Verify error detection (non-zero syndrome)
        syndrome = await tqv.read_reg(4)
        assert syndrome != 0, f"Syndrome should be non-zero for error in bit {error_bit}"
        
        dut._log.info(f"Successfully corrected error in bit {error_bit}, syndrome: {syndrome:02x}")
    
    dut._log.info("Single-bit error correction tests passed!")

@cocotb.test()
async def test_register_readback(dut):
    """Test register readback functionality"""
    tqv = await setup_test(dut)
    dut._log.info("Testing register readback functionality")
    
    # Test encoder input register
    test_value = 0x7
    await tqv.write_reg(0, test_value)
    await ClockCycles(dut.clk, 2)
    
    readback = await tqv.read_reg(0)
    assert readback == test_value, f"Encoder input readback failed: {readback:02x}"
    
    # Test received data register
    test_received = 0x55
    await tqv.write_reg(3, test_received)
    await ClockCycles(dut.clk, 2)
    
    readback = await tqv.read_reg(2)
    assert readback == test_received, f"Received data readback failed: {readback:02x}"
    
    dut._log.info("Register readback tests passed!")

@cocotb.test()
async def test_reset_functionality(dut):
    """Test reset functionality"""
    tqv = await setup_test(dut)
    dut._log.info("Testing reset functionality")
    
    # Set test values in registers
    await tqv.write_reg(0, 0xD)
    await tqv.write_reg(3, 0x69)
    await ClockCycles(dut.clk, 2)
    
    # Verify values are set
    encoded = await tqv.read_reg(1)
    assert encoded != 0, "Encoder should have non-zero output"
    
    # Perform reset
    await tqv.reset()
    await ClockCycles(dut.clk, 2)
    
    # Verify all registers are reset to zero
    registers = [
        (0, "Encoder input"),
        (1, "Encoded output"), 
        (2, "Received data"),
        (3, "Decoded output"),
        (4, "Syndrome")
    ]
    
    for addr, name in registers:
        value = await tqv.read_reg(addr)
        assert value == 0, f"{name} not reset (addr {addr})"
    
    dut._log.info("Reset functionality test passed!")

@cocotb.test()
async def test_comprehensive_hamming(dut):
    """Comprehensive test of all 4-bit patterns and error correction"""
    tqv = await setup_test(dut)
    dut._log.info("Running comprehensive Hamming code test")
    
    # Test all possible 4-bit input patterns
    for pattern in range(16):
        # Test encoding/decoding without errors
        await tqv.write_reg(0, pattern)
        await ClockCycles(dut.clk, 2)
        
        encoded = await tqv.read_reg(1)
        
        await tqv.write_reg(3, encoded)
        await ClockCycles(dut.clk, 2)
        
        decoded = await tqv.read_reg(3)
        syndrome = await tqv.read_reg(4)
        
        assert decoded == pattern, f"Pattern {pattern:02x} failed: decoded {decoded:02x}"
        assert syndrome == 0, f"Syndrome non-zero for pattern {pattern:02x}"
        
        # Test single-bit error correction (flip LSB)
        corrupted = encoded ^ 0x01
        await tqv.write_reg(3, corrupted)
        await ClockCycles(dut.clk, 2)
        
        decoded_corrected = await tqv.read_reg(3)
        syndrome_err = await tqv.read_reg(4)
        
        assert decoded_corrected == pattern, f"Error correction failed for pattern {pattern:02x}"
        assert syndrome_err != 0, f"Syndrome should be non-zero for error case"
    
    dut._log.info("Comprehensive Hamming test passed!")
