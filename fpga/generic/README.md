# Running TinyQV on FPGA

The setup in this directory should allow you to run small TinyQV test programs on FPGA, without needing a QSPI Pmod.

You will need to adapt things for your own FPGA.

## Configuring TinyQV

The competition version of TinyQV with all the peripherals enabled may be too large for your FPGA - you should edit the `peripherals.v` file in this directory to enable only the peripheral(s) that you want to test.  Leave all the other slots set to `tqvp_full_empty` or `tqvp_byte_empty` as appropriate.

The checked in version has only the ws2812b peripheral enabled, to go with the ledstrip.hex test program.  If you have a large FPGA you may be able to enable everything.

The ROM and RAM that would normally be provided by the QSPI Pmod are instead provided by `sim_qspi.v`.  Configure the size by changing the `ROM_BITS` and `RAM_X_BITS` parameters.  These should be inferred into block RAM by your FPGA toolchain.

Set the clock frequency you will provide in MHz at in `top.v`.  This sets the timer and default UART baud appropiately.

## Building TinyQV

The Makefile provides an example of building for ICE40 UP5k using oss cad suite, with pin constraints for pico-ice.  You will need to adjust this for your FPGA.

The program is expected as a hex file, and is specified by the `PROG_FILE` define.  This is set by `PROG` in the example Makefile.

## Using TinyQV

To create programs, see the [tinyQV SDK](https://github.com/MichaelBell/tinyQV-sdk/tree/ttsky25a) and [example projects](https://github.com/MichaelBell/tinyQV-projects).

In order for your programs to fit in the reduced size RAM and ROM, change the Makefile to use `memmap_sim` instead of `memmap`, and link with `tinyQV-sim.a` instead of `tinyQV.a`.  You should adjust the size of the blocks in memmap_sim to match the configuration you set above.

The regular gcc `printf` may bloat your binary too much to fit in your FPGA block RAM.  The `uart_printf` function provided by `uart.h` should be somewhat smaller, or to really minimize size stick to `uart_putc` and `uart_puts`.
