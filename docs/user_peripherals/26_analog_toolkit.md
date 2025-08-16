# Analog toolkit peripheral

Author: htfab

Peripheral index: 26

## What it does

Allows building low frequency ADCs, DACs, capacitive sensors etc. using passives only

(To be expanded)

## Register map

| Address | Name  | Access | Description                                                         |
|---------|-------|--------|---------------------------------------------------------------------|
| 0x00    | OUT0  | W      | Output channel 0 duty cycle: 1b sign, 4b exponent, 3b mantissa      |
| 0x01    | OUT1  | W      | Output channel 1 duty cycle: 1b sign, 4b exponent, 3b mantissa      |
| 0x02    | OUT2  | W      | Output channel 2 duty cycle: 1b sign, 4b exponent, 3b mantissa      |
| 0x03    | IN    | R      | Selected input duty cycle: 1b sign, 4b exponent, 3b mantissa        |
| 0x04    | DIV   | W      | Clock divider: 4b exponent, 4b mantissa                             |
| 0x05    | CH    | W      | Input channel number (0 to 7)

## How to test

Build one of the test circuits:

- ADC
  - connect `ui_in[0]` to the wiper of a 10k linear potmeter on a breadboard
  - add a 100nF capacitor between `ui_in[0]` and `uo_out[1]`
  - connect the other contacts of the potmeter to 3.3V and ground respectively
  - set DIV (register 4) to 0x60 (~64Hz clock)
  - set OUT0 (register 0) to 0x80 (1/2 duty cycle)
  - set CH (register 5) to 0 (set input to `ui_in[0]`)
  - read IN (register 3) for ADC values
  - it won't be perfectly linear but sweeping along the middle 75% of the potmeter's path
    should cover a reasonable range of values, say, 64 to 192

- DAC
  - ...

- Capacitive sensor
  - ...

- LED dimmer
  - ...

## External hardware

Depending on the circuit you want to build it might be useful to have a few

- ceramic capacitors (100nF)
- resistors (100Ω, 10kΩ, 1MΩ)
- potmeters (10kΩ linear)
- standard through-hole LEDs
- and a breadboard with some wires
