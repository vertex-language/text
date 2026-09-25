// Package tokenizer turns text into a model's token ids and back. It is
// data-driven: a vocabulary read from a model's files (a GGUF's
// tokenizer.ggml.* keys, a tokenizer.json) says everything, and no model
// family has code here.
//
// SentencePiece is the tokenizer of Llama 1 and 2, Mistral's first models
// and many more: score-ordered merges of adjacent pieces, with bytes as
// the fallback. It is llama.cpp's llm_tokenizer_spm, rule for rule.
package tokenizer

/// Kind is what a token is, by the numbers GGUF's tokenizer.ggml.token_type
/// and SentencePiece's model give them.
public enum Kind: int {
    case Normal = 1
    case Unknown = 2
    case Control = 3
    case UserDefined = 4
    case Unused = 5
    case Byte = 6
}

/// Vocabulary is a tokenizer's data: each token's text, score and kind by
/// id, the special tokens, and what encoding adds around the text.
public struct Vocabulary {
    public var Tokens: [string]
    public var Scores: [float32]
    public var Kinds: [Kind]
    public var Bos: int?
    public var Eos: int?
    public var Unknown: int?
    /// AddBos is whether Encode puts Bos first (when it adds specials).
    public var AddBos: bool
    /// AddEos is whether Encode puts Eos last (when it adds specials).
    public var AddEos: bool
    /// AddSpacePrefix is SentencePiece's dummy prefix: a space before the
    /// text, so a first word is spelled as every other word is.
    public var AddSpacePrefix: bool

    public init(tokens: [string], scores: [float32], kinds: [Kind], bos: int? = nil, eos: int? = nil,
                unknown: int? = nil, addBos: bool = true, addEos: bool = false, addSpacePrefix: bool = true) {
        self.Tokens = tokens
        self.Scores = scores
        self.Kinds = kinds
        self.Bos = bos
        self.Eos = eos
        self.Unknown = unknown
        self.AddBos = addBos
        self.AddEos = addEos
        self.AddSpacePrefix = addSpacePrefix
    }
}
