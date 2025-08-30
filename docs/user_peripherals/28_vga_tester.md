# Video mode tester peripheral

Author: htfab

Peripheral index: 28

## What it does

There is quite some variability between screens (and VGA/HDMI adapters)
in the set of VGA timing configurations they support.

Due to constraints and optimization pressures, VGA designs on Tiny Tapeout
typically use a single resolution that cannot be changed without a respin.
It would therefore be useful to gather some crowdsourced information on
what VGA modes are well supported among the community.

This peripheral facilitates gathering that information.

It allows setting the horizontal and vertical timing parameters
(visible pixels, front porch, sync pulse, back porch) and displays a
simple test pattern on the screen. There is a thin white border
along the screen edges to quickly check whether anything was cut off.

Each phase (visible pixels, front porch, sync pulse, back porch) is described
by its length in pixels (a 13-bit integer) and 3 single-bit flags.
Internally all 4 phases are identical and the flags are the mechanism
to differentiate their behaviour:
- bit 15: keep hsync/vsync high during this phase
- bit 14: allow data on the r/g/b pins during this phase
- bit 13: advance to the next line/frame at the end of this phase

For instance, a video mode with positive hsync/vsync polarity could use
flags 010 for the visible pixels, 000 for the front porch,
100 for the sync pulse and 001 for the back porch.

## Register map

| Address | Name  | Access | Description                                                         |
|---------|-------|--------|---------------------------------------------------------------------|
| 0x00    | DATA  | R/W    | Horizontal visible pixels, high byte (incl. flags)                  |
| 0x01    | DATA  | R/W    | Horizontal visible pixels, low byte                                 |
| 0x02    | DATA  | R/W    | Horizontal front porch, high byte (incl. flags)                     |
| 0x03    | DATA  | R/W    | Horizontal front porch, low byte                                    |
| 0x04    | DATA  | R/W    | Horizontal sync pulse, high byte (incl. flags)                      |
| 0x05    | DATA  | R/W    | Horizontal sync pulse, low byte                                     |
| 0x06    | DATA  | R/W    | Horizontal back porch, high byte (incl. flags)                      |
| 0x07    | DATA  | R/W    | Horizontal back porch, low byte                                     |
| 0x08    | DATA  | R/W    | Vertical visible pixels, high byte (incl. flags)                    |
| 0x09    | DATA  | R/W    | Vertical visible pixels, low byte                                   |
| 0x0a    | DATA  | R/W    | Vertical front porch, high byte (incl. flags)                       |
| 0x0b    | DATA  | R/W    | Vertical front porch, low byte                                      |
| 0x0c    | DATA  | R/W    | Vertical sync pulse, high byte (incl. flags)                        |
| 0x0d    | DATA  | R/W    | Vertical sync pulse, low byte                                       |
| 0x0e    | DATA  | R/W    | Vertical back porch, high byte (incl. flags)                        |
| 0x0f    | DATA  | R/W    | Vertical back porch, low byte                                       |

## How to test

To use the universally supported 640x480 @ 60 Hz video mode, we would like to set

- Horizontal visible pixels: 640 (high byte 2, low byte 128)
    - 0x00: 66 ("visible" flag adds 64)
    - 0x01: 128
- Horizontal front porch: 16 (high byte 0, low byte 16)
    - 0x02: 0
    - 0x03: 16
- Horizontal sync pulse: 96 (high byte 0, low byte 96)
    - 0x04: 128 ("sync" flag adds 128)
    - 0x05: 96
- Horizontal back porch: 48 (high byte 0, low byte 48)
    - 0x06: 32 ("advance" flag adds 32)
    - 0x07: 48
- Vertical visible pixels: 480 (high byte 1, low byte 224)
    - 0x08: 65 ("visible" flag adds 64)
    - 0x09: 224
- Vertical front porch: 10 (high byte 0, low byte 10)
    - 0x0a: 0
    - 0x0b: 10
- Vertical sync pulse: 2 (high byte 0, low byte 2)
    - 0x0c: 128 ("sync" flag adds 128)
    - 0x0d: 2
- Vertical back porch: 33 (high byte 0, low byte 33)
    - 0x0e: 32 ("advance" flag adds 32)
    - 0x0f: 33

After setting the pixel clock to 25 MHz and writing these registers the test
pattern should appear on the screen connected to the Tiny VGA PMOD.

## External hardware

Tiny VGA PMOD
