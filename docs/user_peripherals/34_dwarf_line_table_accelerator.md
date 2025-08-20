# DWARF Line Table Accelerator

Author: Laurie Hedge

Peripheral index: 34

## What it does

### Overview

The [DWARF file format](https://dwarfstd.org/) is used to store debug information for compiled programs. The line table, the mapping between machine code instructions and the source code it was compiled from, is encoded as a small program targeting an abstract machine. This peripheral is an accelerator for running these line table programs.

### Usage

The peripheral should first be reset at the start of day.

To execute a program, first write the PROGRAM_HEADER register with the fields extracted from the program header in the DWARF file. The packed format of these fields is detailed in the PROGRAM_HEADER section. This will reset the abstract machine and prepare the peripheral for use.

Next, write the code of the program to the PROGRAM_CODE register in a loop. These writes can consist of 1, 2, or 4 bytes at a time, but all bytes must be part of the program. It is suggested to write as much of the program as possible using 4 byte writes, and only use 2 and 1 byte chunks for the remaining bytes at the tail of the program.

After each write to the PROGRAM_CODE register, the STATUS register must be polled. If the status code is STATUS_READY, it is safe to continue to the next iteration of the loop and write to PROGRAM_CODE again. If the status code is STATUS_BUSY, then the register must be polled until the status code changes. If the status code is STATUS_EMIT_ROW, the abstract machine state should be read from the AM registers to emit a row. Then the STATUS register must be written with any value to continue. The STATUS register must be polled again since it could transition into any other status code. If the status code is STATUS_ILLEGAL, then the peripheral has hit an unknown instruction. This error is unrecoverable. The program should be abandoned and the chip should be configured for its next program with a new write to PROGRAM_HEADER.

### Usage Example

The following pseudo-code outlines the expected usage of the peripheral.

```python
def run_program(dwarf_file):
	line_table_program_header = read_line_table_program_header(dwarf_file)
	write_to_reg(PROGRAM_HEADER, pack(line_table_program_header))
	while True:
		status = read_from_reg(STATUS)
		while status == STATUS_BUSY:
			status = read_from_reg(STATUS)
		if status == STATUS_ILLEGAL:
			return False
		if status == STATUS_EMIT_ROW:
			address        = read_from_reg(AM_ADDRESS)
			file_descrim   = read_from_reg(AM_FILE_DISCRIM)
			line_col_flags = read_from_reg(AM_LINE_COL_FLAGS)
			unpack_and_emit_row(address, file_descrim, line_col_flags)
			write_to_reg(STATUS, 0)
			continue
		next_code_chunk = read_code_chunk(dwarf_file)
		if next_code_chunk:
			write_to_reg(PROGRAM_CODE, next_code_chunk)
		else:
			return True
```

### Limitations

This peripheral only supports version 5 of the DWARF format.

Unknown instructions set STATUS to STATUS_ILLEGAL and halt execution of the program, rather than being silently ignored.

Since this peripheral was designed as a companion to the TinyQV CPU, it only support a limited subset of the full DWARF line table accelerator abstract machine. In particular, it has the following limitations.

* The `address` register is limited to 28 bits to match the number of physical address bits supported by TinyQV.
* The `op_index` register is not implemented since it is only used for VLIW, which are not applicable to RV32EC.
* The `file`, `line`, and `discriminator` registers are limited to 16 bits.
* The `column` register is limited to 10 bits.
* The `isa` register is not implemented since only RV32EC is supported.
* The `DW_LNE_define_file` extended opcode, which is deprecated in DWARF v5, is unimplemented, since there is no sensible way of implementing this instruction in a peripheral without greatly extending its scope.

## Registers

Registers may be read or written with 1, 2, or 4 byte accesses. All accesses must be aligned. Unaligned reads always return 0, and unaligned writes are always discarded.

### Register map

| Address | Name              | Access | Description                                |
|---------|-------------------|--------|--------------------------------------------|
| 0x00    | PROGRAM_HEADER    | R/W    | DWARF line table program header.           |
| 0x04    | PROGRAM_CODE      | WO     | DWARF line table program code.             |
| 0x08    | AM_ADDRESS        | RO     | Abstract machine address.                  |
| 0x0C    | AM_FILE_DISCRIM   | RO     | Abstract machine file, and discriminator.  |
| 0x10    | AM_LINE_COL_FLAGS | RO     | Abstract machine line, column, and flags.  |
| 0x14    | STATUS            | R/W    | Status of the peripheral.                  |
| 0x18    | INFO              | RO     | Peripheral version and DWARF file support. |

### PROGRAM_HEADER

This register should be written with the fields read from the line table program header before the program starts.

Writing this register resets the peripheral state and configures the peripheral to run the program.

Reading the register returns the fields of the currently configured program (i.e. the same values that were last written, other than the unused field which will always contain 0).

| 31:24       | 23:16      | 15:8      | 7:1    | 0               |
|-------------|------------|-----------|--------|-----------------|
| opcode_base | line_range | line_base | unused | default_is_stmt |

### PROGRAM_CODE

This register should be written with the line table program code. It can be written in 1, 2, or 4 byte chunks, but every byte written must be part of the program code (no padding) so if the program code is not a multiple of 4 bytes, the 1 or 2 byte variants must be used to write the last bytes.

So long as the write is aligned and falls entirely within this register, it doesn't matter where the code is written to, so a single byte write to 0x04, 0x05, 0x06, or 0x07 would all be the same.

### AM_ADDRESS

This register should only be read when the peripheral has set the STATUS to STATUS_EMIT_ROW.

It contains the address to be emitted for this row.

### AM_FILE_DISCRIM

This register should only be read when the peripheral has set the STATUS to STATUS_EMIT_ROW.

It contains the file and discriminator to be emitted for this row.

| 31:16         | 15:0 |
|---------------|------|
| discriminator | file |

### AM_LINE_COL_FLAGS

This register should only be read when the peripheral has set the STATUS to STATUS_EMIT_ROW.

It contains the line, column, is_stmt, basic_block, end_sequence, prologue_end, and epilogue_begin to be emitted for this row.

| 31     | 30             | 29           | 28           | 27          | 26      | 25:16  | 15:0 |
|--------|----------------|--------------|--------------|-------------|---------|--------|------|
| unused | epilogue_begin | prologue_end | end_sequence | basic_block | is_stmt | column | line |

### STATUS

This register contains the current state of the peripheral. It should generally be polled before writing to PROGRAM_CODE, to ensure that the peripheral is ready to receive more code and that any responses from the peripheral are handled.

Writing any value with a valid aligned access to any part of this register will clear the STATUS_EMIT_ROW state and cause the peripheral to resume running.

#### Status Codes

| Code | Name            | Description |
|------|-----------------|-------------|
| 0x00 | STATUS_READY    | Peripheral is ready to receive writes to PROGRAM_CODE. |
| 0x01 | STATUS_EMIT_ROW | Peripheral has executed an instruction that emits a row, and execution is now paused. Read the row from AM_ADDRESS, AM_FILE_DISCRIM, and AM_LINE_COL_FLAGS. |
| 0x02 | STATUS_BUSY     | Peripheral is busy processing instructions and cannot accept writes to PROGRAM_CODE at this time. |
| 0x03 | STATUS_ILLEGAL  | Peripheral has stopped due to hitting an illegal instruction. |

#### State Transitions

ANY -> STATUS_READY
_on reset_

STATUS_READY -> STATUS_BUSY
_on write to PROGRAM_CODE_

STATUS_EMIT_ROW -> STATUS_BUSY
_on write to STATUS when instructions remain in PROGRAM_CODE_

STATUS_EMIT_ROW -> STATUS_READY
_on write to STATUS when no instructions remain in PROGRAM_CODE_

STATUS_BUSY -> STATUS_READY
_on finish executing intructions in PROGRAM_CODE_

STATUS_BUSY -> STATUS_EMIT_ROW
_on execute instruction that emits a row_

STATUS_BUSY -> STATUS_ILLEGAL
_on execute illegal instruction_

STATUS_ILLEGAL -> STATUS_READY
_on write to STATUS or PROGRAM_HEADER_

### INFO

This register contains information about the version of the hardware and the range of DWARF formats supported.

| 31:8             | 7:4               | 3:0               |
|------------------|-------------------|-------------------|
| hardware version | max dwarf version | min dwarf version |

## How to test

Tests should be run from inside a Docker container using a Docker image built from
tinyqv-dwarf-peripheral/.devcontainer/Dockerfile.

### Unit tests

The unit tests are hand written tests using the cocotb test framework, covering each instruction and various interesting cases.

To run the tests, from inside the Docker container, run
```sh
cd /path/to/ttsky25a-tinyQV/test
make -B tqvp_laurie_dwarf_line_table_accelerator.test
```

### RIS tests

_These are only available in the [peripheral's own repository](https://github.com/laurie-hedge/tinyqv-dwarf-peripheral) and have not been merged to the ttsky25a-tinyQV repository._

Random Instruction Sequence (RIS) tests work by generating a semi-random sequence of instructions to execute, and then running these instructions of both the peripheral (simulated by verilating the HDL) and through a simulator written in C++ which acts as a golden reference. The testbench compares the results of each to ensure they produce the same results. Since these tests are random, they will vary each time the tests are run, so are not run as part of CI.

To run these tests, from inside the Docker container, run
```sh
cd /path/to/tinyqv-dwarf-peripheral/ris-test
make
./obj_dir/testbench --run 100
```

This will run 100 randomly generated tests. You can change the number to run as many tests as you want. If a test fails, it will report the error and save a file called `test.bin`. This file captures the input into the specific test that failed, so that it can be replayed and debugged.

To replay a test.bin file, from the same directory as before, run
```sh
./obj_dir/testbench --rerun test.bin
```

To enable generation of the waves for the test, uncomment this section at the bottom of `tqvp_laurie_dwarf_line_table_accelerator.sv`.
```c
// initial begin
//     $dumpfile("trace.vcd");
//     $dumpvars();
// end
```

## External hardware

No external hardware is required. The Pmod interface is unused by this peripheral.
