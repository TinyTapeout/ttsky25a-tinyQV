<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

The peripheral index is the number TinyQV will use to select your peripheral.  You will pick a free
slot when raising the pull request against the main TinyQV repository, and can fill this in then.  You
also need to set this value as the PERIPHERAL_NUM in your test script.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# INTERCAL ALU

Author: Rebecca G. Bettencourt

Peripheral index: 37

## What it does

As an educational project, it is inevitable that Tiny Tapeout would attract various pedagogical examples of common logic circuits, such as ALUs. While ALUs for common operations such as addition, subtraction, and binary bitwise logic are surprisingly common, it is much rarer to encounter one that can calculate the five operations of the INTERCAL programming language. Due to either the cost-prohibitive nature of Warmenhovian logic gates or general lack of interest, such a feat has never been performed until now. With chip production finally within reach of the average person, all it takes is one person who has more dollars than sense to design the fabled INTERCAL ALU (Arrhythmic Logic Unit).

This peripheral implements such an ALU. It has two 32-bit registers, B and A (in no particular order). (These may also be thought of as four 16-bit registers, AL, AH, BL, and BH.) These are accessible at addresses 0x00-0x07. The results of the five INTERCAL operations are accessible at addresses 0x08-0x2F.

Addresses 0x08-0x1F correspond to INTERCAL's unary AND, unary OR, and unary XOR operators, represented by ampersand (&), book (V), and what (?), respectively. From the INTERCAL manual:

<blockquote>
These operators perform their respective logical operations on all pairs of adjacent bits, the result from the first and last bits going into the first bit of the result. The effect is that of rotating the operand one place to the right and ANDing, ORing, or XORing with its initial value. Thus, <code>#&77</code> (binary = 1001101) is binary 0000000000000100 = 4, <code>#V77</code> is binary 1000000001101111 = 32879, and <code>#?77</code> is binary 1000000001101011 = 32875.
</blockquote>

The results at 0x08, 0x0A, 0x10, 0x12, 0x18, 0x1A are calculated from the 16-bit halves of the A register independently, while the results at 0x0C, 0x14, 0x1C are calculated from the 32-bit whole of the A register.

Addresses 0x20-0x27 correspond to INTERCAL's *interleave* (also called *mingle*) operator, represented by big money (&#36;). From the INTERCAL manual:

<blockquote>
The interleave operator takes two 16-bit values and produces a 32-bit result by alternating the bits of the operands. Thus, <code>#65535&#36;#0</code> has the 32-bit binary form 101010....10 or 2863311530 decimal, while <code>#0&#36;#65535</code> = 0101....01 binary = 1431655765 decimal, and <code>#255&#36;#255</code> is equivalent to <code>#65535</code>.
</blockquote>

Address 0x20 returns the interleave of the lower halves of A and B, while address 0x24 returns the interleave of the upper halves of A and B.

Addresses 0x28-0x2F correspond to INTERCAL's *select* operator, represented by sqiggle (~). From the INTERCAL manual:

<blockquote>
The select operator takes from the first operand whichever bits correspond to 1's in the second operand, and packs these bits to the right in the result. Both operands are automatically padded on the left with zeros. […] For example, <code>#179~#201</code> (binary value 10110011~11001001) selects from the first argument the 8th, 7th, 4th, and 1st from last bits, namely, 1001, which = 9. But <code>#201~#179</code> selects from binary 11001001 the 8th, 6th, 5th, 2nd, and 1st from last bits, giving 10001 = 17. <code>#179~#179</code> has the value 31, while <code>#201~#201</code> has the value 15.
</blockquote>

To help understand the select operator, the INTERCAL manual also provides a helpful [circuitous diagram](https://www.muppetlabs.com/~breadbox/intercal-man/figure1.html).

Use of addresses 0x30-0x3F is not recommended, unless undefined behavior is required.

## Register map

| Address | Name      | Access | Description                                                     |
|---------|-----------|--------|-----------------------------------------------------------------|
| 0x00    | A         | R/W 32 | Left side argument, 32 bits.                                    |
| 0x00    | AL        | R/W 16 | Left side argument, low 16 bits.                                |
| 0x02    | AH        | R/W 16 | Left side argument, high 16 bits.                               |
| 0x04    | B         | R/W 32 | Right side argument, 32 bits.                                   |
| 0x04    | BL        | R/W 16 | Right side argument, low 16 bits.                               |
| 0x06    | BH        | R/W 16 | Right side argument, high 16 bits.                              |
| 0x08    | AND16L    | R 16   | & AL (16-bit unary AND of AL)                                   |
| 0x0A    | AND16H    | R 16   | & AH (16-bit unary AND of AH)                                   |
| 0x0C    | AND32     | R 32   | & A (32-bit unary AND of A)                                     |
| 0x10    | OR16L     | R 16   | V AL (16-bit unary OR of AL)                                    |
| 0x12    | OR16H     | R 16   | V AH (16-bit unary OR of AH)                                    |
| 0x14    | OR32      | R 32   | V A (32-bit unary OR of A)                                      |
| 0x18    | XOR16L    | R 16   | ? AL (16-bit unary XOR of AL)                                   |
| 0x1A    | XOR16H    | R 16   | ? AH (16-bit unary XOR of AH)                                   |
| 0x1C    | XOR32     | R 32   | ? A (32-bit unary XOR of A)                                     |
| 0x20    | MINGLE16L | R 32   | AL &#36; BL (interleave of AL and BL)                           |
| 0x24    | MINGLE16H | R 32   | AH &#36; BH (interleave of AH and BH)                           |
| 0x28    | SELECT16L | R 16   | AL ~ BL (16-bit select of AL and BL)                            |
| 0x2A    | SELECT16H | R 16   | AH ~ BH (16-bit select of AH and BH)                            |
| 0x2C    | SELECT32  | R 32   | A ~ B (32-bit select of A and B)                                |

The peripheral supports 32-bit access to any multiple of 4 and 16-bit access to any even address.
This means you can read two 16-bit results at once or half of a 32-bit result if you want.

## How to test

The following example calculations found in the INTERCAL manual should be particularly illuminating.

| S                  | A     | B     | F          |
| ------------------ | ----- | ----- | ---------- |
| `MINGLE16L` (0x20) | 0     | 256   | 65536      |
| `MINGLE16L` (0x20) | 65535 | 0     | 2863311530 |
| `MINGLE16L` (0x20) | 0     | 65535 | 1431655765 |
| `MINGLE16L` (0x20) | 255   | 255   | 65535      |
| `SELECT16` (0x28)  | 51    | 21    | 5 *        |
| `SELECT16` (0x28)  | 179   | 201   | 9          |
| `SELECT16` (0x28)  | 201   | 179   | 17         |
| `SELECT16` (0x28)  | 179   | 179   | 31         |
| `SELECT16` (0x28)  | 201   | 201   | 15         |
| `AND16` (0x08)     | 77    |       | 4          |
| `OR16` (0x10)      | 77    |       | 32879      |
| `XOR16` (0x18)     | 77    |       | 32875      |

These test cases are included in the (unfortunately Python and not INTERCAL) `test.py` file. As these are likely more INTERCAL operations than any sensible person will ever perform, they should be sufficient for testing purposes. However, for curiosity's sake, an extensive set of additional test cases have also been included.

\* Not found in the INTERCAL manual.

## Further reading

[The INTERCAL Programming Language Revised Reference Manual](https://www.muppetlabs.com/~breadbox/intercal-man/home.html) by Donald R. Woods and James M. Lyon with revisions by Louis Howell and Eric S. Raymond (can recommend highly enough)
