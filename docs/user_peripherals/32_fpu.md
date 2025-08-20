# Hal-precision Floating Point Unit (FPU)

Author: Diego Satizanal

Peripheral index: 32

## What it does

This project implements a **half-precision IEEE-754 compliant Floating Point Unit (FPU)** compatible with the TinyQV SPI register interface. The FPU supports:

- **Addition**
- **Subtraction**
- **Multiplication**

The operands and results are encoded using **16-bit half-precision floating point format** as defined in the IEEE 754 standard. The design is fully synchronous and modular, comprising three main components:

- `fpu_add_pipelined`: Performs pipelined IEEE-754 compliant addition and subtraction
- `fpu_mult_pipelined`: Performs pipelined IEEE-754 compliant multiplication
- `tqvp_dsatizabal_fpu`: Top-level integration module with memory-mapped register interface

The FPU handles normal, subnormal, zero, infinity, and NaN values. It also includes tests for edge cases to ensure correctness under various input scenarios.

## Register map

The FPU communicates via a **memory-mapped register interface** exposed over SPI. The interface is organized as follows:

| Address | Name      | Access | Description                                                   |
| ------- | --------- | ------ | ------------------------------------------------------------- |
| 0x00    | Operand A | Write  | Lower 16 bits: First operand (used in ADD)                    |
| 0x01    | Operand B | Write  | Lower 16 bits: Second operand (used in ADD)                   |
| 0x04    | Operand A | Write  | Lower 16 bits: First operand (used in SUB)                    |
| 0x05    | Operand B | Write  | Lower 16 bits: Second operand (used in SUB)                   |
| 0x08    | Operand A | Write  | Lower 16 bits: First operand (used in MUL)                    |
| 0x09    | Operand B | Write  | Lower 16 bits: Second operand (used in MUL)                   |
| 0x0C    | Result    | Read   | Lower 16 bits: Result of most recent floating-point operation |
| 0x10    | Busy      | Read   | Bit[0] = 1 when busy, 0 when idle                             |

## How to test

Tests were implemented using CocoTB, including tests for the individual modules (Adder/Multiplier/FPU) and the TinyQV Integration test

> [!IMPORTANT]  
> The following instructions apply only for the original repository, please refer to TinyQV documentation to run tests in the integrated shuttle repository

1. **Standalone Simulation:**

   - Create a Virtual env, cna be in any folder but we recommend using the [test/components](/test/components/) folder:
    ```bash
     python3 -m venv .venv
     ```
   - Install the `requirements.txt`:
    ```bash
    pip install -r requirements.txt
    ```
   - Observe that there are folders for each component, inside each you can synth (YoSys), test (cocotb) or view (GTKWave):
    ```bash
     make synth
     make test
     make view
     ```

2. **Integration Testing with SPI Interface (TinyQV):**

   - Use the provided `tt_um_tqv_peripheral_harness.v` to simulate SPI register interaction
   - Execute system-level Cocotb tests via `tb.v` testbench
   - This simulates the behavior as if the FPU were accessed by a RISC-V processor

    ```bash
     make -B
     ```

## External hardware

- No external hardware required
- Compatible with SPI-based Tiny Tapeout QV test infrastructure

## Requirements

- Python 3.8+
- Cocotb 1.9.2
- Numpy >= 1.26
- Icarus Verilog (for simulation)
- YoSys for synthesis (optional)
- GTKWave for waveforms analysis and debugging

Dependencies listed in `requirements.txt`:

```text
pytest==8.3.4
cocotb==1.9.2
numpy>=1.26
```

## Limitations

- Only supports **addition, subtraction, and multiplication**
- Does not support division, square root, fused multiply-add, etc.
- Operands and result are constrained to **IEEE-754 half-precision (16-bit)** format
- Rounding and normalization are simplified; accuracy matches float16 precision but not beyond
- Pipeline latency varies by operation and is not exposed
- No exception flags or traps (e.g., underflow/overflow detection)

## Further improvements

- Add division and square root modules
- Implement fused multiply-add (FMA)
- Extend to support single-precision (32-bit float)
- Include pipeline stall/flush control
- Add support for exception flags (NaN, overflow, underflow)
- Hardware area and power optimization (for ASIC targeting)
- Formal verification coverage

## Background: IEEE-754 Half-Precision Format (16-bit)

The IEEE-754 16-bit binary floating point format is structured as follows:

| Field    | Width   | Description                    |
| -------- | ------- | ------------------------------ |
| Sign     | 1 bit   | 0 for positive, 1 for negative |
| Exponent | 5 bits  | Biased exponent (bias = 15)    |
| Fraction | 10 bits | Significant (mantissa) bits    |

### Special encodings:

- **0x0000**: +0.0
- **0x8000**: -0.0
- **Exp = 0x1F, Frac = 0x000**: ±Infinity
- **Exp = 0x1F, Frac ≠ 0x000**: NaN
- **Exp = 0x00, Frac ≠ 0x000**: Subnormal numbers

This project handles all these special cases as part of arithmetic computation.

---

> Developed by Diego Satizabal for the Tiny Tapeout QV FPU Challenge, 2025

