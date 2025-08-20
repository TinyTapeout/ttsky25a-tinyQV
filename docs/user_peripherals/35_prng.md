<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

The peripheral index is the number TinyQV will use to select your peripheral.  You will pick a free
slot when raising the pull request against the main TinyQV repository, and can fill this in then.  You
also need to set this value as the PERIPHERAL_NUM in your test script.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# xoshiro128++ pseudorandom number generator

Author: Ciro Cattuto

Peripheral index: 35

## What it does

The peripheral implements the pseudorandom number genetor [xoshiro128++ PRNG](https://prng.di.unimi.it/xoshiro128plusplus.c). Reading register RND (0x00) yields the current value of the generator and triggers computation of the next value, which completes in 1 clock cycle. The peripheral can generate one new pseudorandom number per clock cycle. The internal state of the random number generator (4 32-bit words) can be set using registers S0, S1, S2 and S3. After writing to any of these registers, a dummy read of register RND is necessary before reading the first pseudorandom number of the new sequence. Only supports 32-bit reads and writes.

## Register map

Document the registers that are used to interact with your peripheral

| Address | Name  | Access | Description                                                         |
|---------|-------|--------|---------------------------------------------------------------------|
| 0x00    | RND   | R      | Next 32-bit pseudorandom number                                     |
| 0x01    | S0    | W      | Write RNG state word S0                                             |
| 0x02    | S1    | W      | Write RNG state word S1                                             |
| 0x03    | S2    | W      | Write RNG state word S2                                             |
| 0x04    | S3    | W      | Write RNG state word S3                                             |

## How to test

Read register RND right after boot. It should yield 0xFEF316C3. Read the same register to generate new pseudorandom numbers.

## External hardware

No external hardware required.
