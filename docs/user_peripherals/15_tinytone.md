# TinyTone PWM Peripheral

**Author:** pranav0x0112(Pranav)

## Overview

TinyTone is a simple PWM-based tone generator peripheral for the TinyQV SoC. It generates square wave audio tones at programmable frequencies, suitable for sound output or simple beeping.

- Written in Bluespec SystemVerilog (BSV), auto-generated to Verilog.
- Integrated as user peripheral slot 15.
- Exposes registers for frequency and enable control.
- Output is available on the assigned user output pin.

## How it works

The peripheral receives a frequency value via a register write. It uses a counter to generate a PWM square wave at the requested frequency. The output toggles between high and low, producing an audible tone when connected to a speaker or piezo buzzer.

## Register Map

| Register         | Address Offset | Description                |
|------------------|---------------|----------------------------|
| Frequency        | 0x00          | Set output frequency (Hz)  |
| Enable           | 0x04          | 1 = enable, 0 = disable    |
| Status           | 0x08          | Read current state         |

## Example Usage

1. Write the desired frequency to the frequency register.
2. Set the enable register to 1.
3. The output pin will produce a square wave at the set frequency.