# text/tokenizer

Turns text into a model's token ids and back. It is data-driven: a vocabulary read from a model's files (a GGUF's tokenizer.ggml.* keys, a tokenizer.json) says everything, and no model family has code here.

```vertex
import "text/tokenizer"
```

## Types

- **`Split`** (enum): Split is how text is cut into words before byte-level BPE merges within each: the pre-tokenizer regex of the model's tokenizer.json, as llama.cpp implements each by hand (src/unicode.cpp).
- **`BPE`** (class): BPE is byte-level byte-pair encoding, GPT-2's: text cut into words by its Split, each word's bytes spelled as printable characters (GPT-2's bytes_to_unicode), then merged pairwise, the lowest-ranked merge first, into the vocabulary's tokens.
- **`SentencePiece`** (class): SentencePiece encodes and decodes with a vocabulary.
- **`ModelError`** (enum): ModelError is a tokenizer file that could not be read, and why.
- **`Algorithm`** (enum): Algorithm is how a vocabulary turns text into tokens.
- **`Tokenizer`** (class): Tokenizer is a model's tokenizer, whatever its algorithm: what a model holds, and never asks which.
- **`Kind`** (enum): Kind is what a token is, by the numbers GGUF's tokenizer.ggml.token_type and SentencePiece's model give them.
- **`Vocabulary`** (struct): Vocabulary is a tokenizer's data: each token's text, score and kind by id, the special tokens, and what encoding adds around the text.

## Functions

- `func ReadTokenizerJSON(_ bytes: [uint8], config: [uint8]? = nil) throws -> Tokenizer`: ReadTokenizerJSON is the tokenizer a Hugging Face tokenizer.json holds, with what tokenizer_config.json (when given) says of BOS, EOS and adding them.
- `func ReadSentencePieceModel(_ bytes: [uint8]) throws -> Vocabulary`: ReadSentencePieceModel is the vocabulary in a SentencePiece model file (tokenizer.model: a ModelProto, protobuf): each piece's text, score and type, the unknown, BOS and EOS ids from its trainer spec, and whether its normalizer adds the dummy prefix.

Part of the [`text`](https://github.com/vertex-language/text) repository.
