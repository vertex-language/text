# text

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![text: font | tokenizer](https://img.shields.io/badge/text-font%20%7C%20tokenizer-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/text)

Text, as algorithms rather than formats: fonts and shaping, and tokenizers for language models. HTML and CSS are the `web` repository's.

---

## Packages

- **`text/font`**: Faces by family, size, weight and slant; text shaped into glyphs with a per-word cache; glyph masks at any scale, drawn onto an `image/draw` canvas. The OS shapes and rasterizes: CoreText on macOS (`font.cpp`, module `text.font`, and `font_darwin.mm`).
- **`text/tokenizer`**: Text to a model's token ids and back, driven by the model's vocabulary data. `SentencePiece` works as llama.cpp's `llm_tokenizer_spm` does: score-ordered merges of adjacent pieces, `▁` for spaces, a dummy prefix, and `<0xXX>` byte fallback. `Encode`, `Decode` (with llama.cpp's leading-space rule) and `Piece` (a token's bytes, for streaming). A `Vocabulary` holds tokens, scores and kinds, the special ids, and whether BOS, EOS and the space prefix are added. It is built from a GGUF file's `tokenizer.ggml.*` keys (`model/llama.Vocabulary`).

---

## Quick Start

```bash
vsc run check-font
vsc run test-tokenizer
vsc run test-bpe
```

---

## Running Tests

Execute the comprehensive test suite directly with `vsc`:

```bash
vsc run check-font
vsc run test-tokenizer
```

`test-tokenizer` runs llama.cpp's own tokenizer test for Llama 2's SentencePiece vocabulary: `cmd/test-tokenizer/testdata`, `ggml-vocab-llama-spm.gguf` with its 46 inputs and expected ids, from llama.cpp (MIT). It also checks encoding with `<s>` and decoding both ways against what libllama makes of the same inputs (`golden/`, from `oracle/tokenize_dump.cpp`). All 46 inputs match in all three.

---

## License

[MIT](LICENSE)
