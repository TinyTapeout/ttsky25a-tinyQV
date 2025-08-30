<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.
The peripheral index is the number TinyQV will use to select your peripheral. You will pick a free
slot when raising the pull request against the main TinyQV repository, and can fill this in then. You
also need to set this value as the PERIPHERAL_NUM in your test script.
You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# Hamming (7,4) Error Correction Code

Author: Enmanuel Rodriguez  
Peripheral index: 31

## What it does

This peripheral implements a Hamming (7,4) error correction code system that can detect and correct single-bit errors in 4-bit data. The module provides both encoding and decoding functionality:

**Encoder**: Takes a 4-bit data input and generates a 7-bit codeword with 3 parity bits for error detection and correction.

**Decoder**: Takes a 7-bit received codeword, detects if there's a single-bit error, corrects it if found, and extracts the original 4-bit data.

The Hamming code uses the bit arrangement: `{d3, d2, d1, p2, d0, p1, p0}` where:
- d3, d2, d1, d0 are the 4 data bits
- p2, p1, p0 are the 3 parity bits
- Bit positions are indexed from 0 (LSB) to 6 (MSB)

## Register map

| Address | Name | Access | Description |
|---------|-------|--------|---------------------------------------------------------------------|
| 0x00 | ENC_INPUT | R/W | Encoder input data (4 bits in lower nibble). Writing triggers encoding. |
| 0x01 | ENCODED | R | Encoded 7-bit codeword (in lower 7 bits) |
| 0x02 | RECEIVED | R | Last received codeword for decoding (7 bits in lower 7 bits) |
| 0x03 | DEC_INPUT | R/W | Decoder input (7 bits in lower 7 bits). Writing triggers decoding. |
| 0x04 | DECODED | R | Decoded 4-bit data (in lower nibble) |
| 0x05 | SYNDROME | R | Syndrome bits indicating error position (3 bits). 0 = no error. |

**Note**: The module uses a single `data_in` input for both encoding and decoding operations, selected by the address during write operations.

## How to test

1. **Encoding Test**:
   - Write a 4-bit value to register 0x00 (ENC_INPUT)
   - Read register 0x01 (ENCODED) to get the 7-bit Hamming-encoded result

2. **Decoding Test (No Error)**:
   - Write a valid 7-bit Hamming code to register 0x03 (DEC_INPUT)
   - Read register 0x04 (DECODED) to verify the original 4-bit data is recovered
   - Read register 0x05 (SYNDROME) to confirm it's 0 (no error detected)

3. **Error Correction Test**:
   - Write a 7-bit code with a single-bit error to register 0x03
   - Read register 0x05 (SYNDROME) to see the error position (1-7, where 0 means no error)
   - Read register 0x04 (DECODED) to verify the data was correctly recovered

Example test sequence:
```
Write 0x0A (1010) to address 0x00 → Read address 0x01 for encoded value
Write encoded value to address 0x03 → Read address 0x04 should return 0x0A, address 0x05 should be 0
Flip one bit in encoded value and write to address 0x03 → Read address 0x04 should still return 0x0A
```

## Parity Bit Calculations

The parity bits are calculated as follows:
- p0 (bit 0): XOR of data bits d0, d1, d3
- p1 (bit 1): XOR of data bits d0, d2, d3  
- p2 (bit 3): XOR of data bits d1, d2, d3

## Error Detection and Correction

The syndrome calculation checks parity across specific bit positions:
- syndrome[0]: XOR of bits 0, 2, 4, 6
- syndrome[1]: XOR of bits 1, 2, 5, 6
- syndrome[2]: XOR of bits 3, 4, 5, 6

A non-zero syndrome indicates the position of a single-bit error, which is automatically corrected before data extraction.

## External hardware

No external hardware required. This is a pure digital processing peripheral that operates entirely through register-based interfaces.