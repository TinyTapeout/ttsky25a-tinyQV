# PDM: Pulse Density Modulation Decoder

Author: Jon Nordby, Martin Stensgård

Peripheral index: 10

## What it does

The PDM peripheral outputs a bit clock signal for a PDM microphone,
and decodes the returned density signal into Pulse Code Modulation (PCM) words.

## Register map

| Address | Name  | Access | Description                                                         |
|---------|-------|--------|---------------------------------------------------------------------|
| 0x00    | CTRL  | R/W    | PDM control.                                                        |
| 0x04    | CLKP  | R/W    | PDM clock period (0-64).                                            |
| 0x08    | PCMW  | R      | PCM word, result of conversion.                                     |

### CTRL
Bit 0: Enable clock generation.

### CLKP
Number of system clock cycles per PDM clock cycle.
For example, to generate a 1 MHz clock signal, set this to 64.

### PCMW
16-bit signed integer.

## How to test

In this example we generate 15 625 PCM samples per second,
by generating a 1 MHz PDM bit clock,
assuming the microcontroller's clock is running at 14 MHz:

1. Write 14 (cpu clk per pdm clk) to address 4 (CLKP) to set PDM frequency.
2. Write 1 to address 0 (CTRL) to start this peripheral running.
3. Every time this peripheral interrupts, read PCM sample from address 8.
4. Do something interesting with the audio samples! :)

## External hardware

Adafruit PDM MEMS Microphone Breakout
https://www.adafruit.com/product/3492
