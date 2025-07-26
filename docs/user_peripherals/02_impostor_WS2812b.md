<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## What it does

This module emulates the behavior of a WS2812B addressable RGB LED. It is designed to integrate  into a daisy-chained WS2812B LED strip, acting as a "virtual LED" or "impostor" within the chain.

It receives data on the `DIN` input pin (typically connected to the previous LED in the chain or a microcontroller), extracts and stores the RGB values destined for it, and then forwards the remaining data to the next element in the chain via the `DOUT` output pin. 

This passthrough behavior mimics that of a real WS2812B LED. This allows the module to coexist with actual LEDs or other impostor modules in a daisy-chain configuration.

- Fully compatible timing and protocol emulation with WS2812B devices.
- Can be inserted anywhere in a WS2812B LED chain.
- Extracts and stores the first RGB triplet received (24 bits: G, R, B).
- Exposes internal state via a simple memory-mapped register interface.
- Supports external clearing of the `rgb_ready` latch to detect new data arrivals.    

Applications:
- Simulation or logging tools for WS2812B protocols.
- Its cool as hell, how about instead of colours we control servos.

## Register Map

| Address | Name        | Access | Description                                                                 |
|---------|-------------|--------|-----------------------------------------------------------------------------|
| 0x00    | `reg_r`     | R      | Last received **Red** byte                                                  |
| 0x01    | `reg_g`     | R      | Last received **Green** byte                                               |
| 0x02    | `reg_b`     | R      | Last received **Blue** byte                                                |
| 0x0E    | `rgb_clear` | W      | Write `0x00` to clear `rgb_ready`; resets to `0x01` internally after toggle |
| 0x0F    | `rgb_ready` | R      | `0xFF` if new RGB data received (latched), `0x00` after cleared by `rgb_clear` |

> Nota: The WS2812B protocol sends colors in **GRB** order. This peripheral captures and reorders them internally for convenience.

## How to Test

1. Connect a WS2812B signal generator (e.g. microcontroller or FPGA) to the `DIN` input (`ui_in[1]`).
2. Transmit a standard WS2812B data frame with one or more 3-byte RGB values.
3. Once the first 8x3=24 bits are received, the peripheral will:
   - Store the values in the internal registers.
   - Set the `rgb_ready` register to `0xFF` to indicate data availability.
4. The user can now read:
   - `reg_r` (0x00) for RED
   - `reg_g` (0x01) for GREEN
   - `reg_b` (0x02) for BLUE
5. To acknowledge the data and re-arm the peripheral for new RGB input:
   - Write `0x00` to the `rgb_clear` register (0x0E)
   - The `rgb_ready` flag will automatically reset to `0x00`

## External Hardware

- **WS2812B Driver or Controller** (e.g. microcontroller, FPGA logic, cheap chinese led driver)
- **Additional WS2812B LEDs or Impostor Modules**:
  This peripheral supports forwarding of the remaining data to downstream LEDs via the `DOUT` pin, enabling full compatibility with mixed chains of real and imposter devices.



