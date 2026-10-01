# text/font

Faces by family, size, weight and slant; text shaped into glyphs with a per-word cache; glyph masks at any scale, drawn onto an `image/draw` canvas. The OS shapes and rasterizes: CoreText on macOS (`font.cpp`, module `text.font`, and `font_darwin.mm`).

```vertex
import "text/font"
```

## Types

- **`Spec`** (struct): What a font is asked for, in CSS terms: a list of families to try in order, a size in CSS pixels, a weight from 100 to 900 and a slant.
- **`Run`** (struct): Text shaped into glyphs: what to draw, on which face, and how far each advances the pen, in CSS pixels.
- **`Face`** (class): A font at one size. Faces are shared: `Load` answers the same one for the same spec, and each keeps what it has shaped.
- **`Glyph`** (struct): A glyph's coverage, rasterized at some scale: the mask, and where its top-left corner sits relative to the glyph's origin on the baseline, in device pixels.

## Functions

- `func Register(path: string, as name: string) -> bool`: Registers a font file so that its family can be used, under the name given, as @font-face does. Answers false where the file is not a font.
- `func RegisterData(_ data: [uint8], as name: string) -> bool`: Registers a font from its bytes -- a TrueType or OpenType file, as a page's @font-face fetches one -- under the name given.
- `func Load(_ spec: Spec) -> Face`: The face for a spec: the first of its families the system has, at the size, weight and slant asked for, or the platform's sans-serif where it has none of them.
- `func GlyphMask(face: int32, glyph: uint32, scale: float32) -> Glyph`: The mask for a glyph of a face at a scale, rasterized once and kept. Scales are kept to sixteenths, which is finer than any display's.
- `func DrawRun(_ canvas: draw.Canvas, _ run: Run, x: float32, baseline: float32, scale: float32, color: draw.Color)`: Draws a run on a canvas with its origin at (x, baseline) in device pixels, at a scale: the glyphs are rasterized at that scale and each pen advance is scaled to match.

Part of the [`text`](https://github.com/vertex-language/text) repository.
