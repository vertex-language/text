# text/bidi

The Unicode Bidirectional Algorithm (UAX #9): the embedding level of each character of a paragraph, and the order a line's characters show in. Explicit embeddings, overrides and isolates (X1 to X10), the weak types (W1 to W7), paired brackets (N0), neutrals (N1, N2) and implicit levels (I1, I2); L1 for a line; L2 for the visual order. Bidi_Class comes from the `unicode` package.

```vertex
import "text/bidi"
```

## Types

- **`Direction`** (enum): A paragraph's or an embedding's direction, `ltr` or `rtl`.

## Functions

- `func Levels(_ text: [uint32], base: Direction?) -> (levels: [uint8], base: uint8)`: The embedding levels of a paragraph's characters, and the paragraph's own level. With no base direction the first strong character chooses it (left to right where there is none).
- `func LineLevels(_ text: [uint32], _ levels: [uint8], base: uint8, from: int, to: int) -> [uint8]`: The levels of a line of a paragraph, after L1: separators, and the whitespace before them or at the line's end, go to the paragraph's level.
- `func VisualOrder(_ levels: [uint8]) -> [int]`: The order a line's characters show in, left to right, as indexes (L2).
- `func Mirror(_ cp: uint32) -> uint32`: The character shown in cp's place at an odd level: a bracket's or other mirrored character's pair.
- `func HasRightToLeft(_ text: [uint32]) -> bool`: Whether text holds anything that could put a character right to left.
- `func FirstStrong(_ text: [uint32]) -> Direction?`: The direction of the first strong character, skipping what isolates hold (P2, P3).

Shaping is not here: `text/font` shapes a run of one direction, and CoreText orders the glyphs inside it.
