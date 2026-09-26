package tokenizer

/// Algorithm is how a vocabulary turns text into tokens.
public enum Algorithm {
    /// SentencePiece's score-ordered merges with byte fallback: Llama 1
    /// and 2, Mistral's first models, T5.
    case sentencePiece(SentencePiece)
    /// Byte-level BPE, GPT-2's: GPT-2, Llama 3, Qwen, SmolLM, Mistral's
    /// newer models, most models since.
    case bpe(BPE)
}

/// Tokenizer is a model's tokenizer, whatever its algorithm: what a model
/// holds, and never asks which. (Byte-level BPE and WordPiece join
/// Algorithm as models need them.)
public final class Tokenizer {
    public let Algorithm: Algorithm

    public init(_ algorithm: Algorithm) {
        self.Algorithm = algorithm
    }

    /// SentencePiece is a SentencePiece tokenizer of vocab.
    public static func SentencePiece(_ vocab: Vocabulary) -> Tokenizer {
        return Tokenizer(.sentencePiece(tokenizer.SentencePiece(vocab)))
    }

    /// BPE is a byte-level BPE tokenizer of vocab, its words cut by split.
    public static func BPE(_ vocab: Vocabulary, split: Split, ignoreMerges: bool? = nil) -> Tokenizer {
        return Tokenizer(.bpe(tokenizer.BPE(vocab, split: split, ignoreMerges: ignoreMerges)))
    }

    /// Vocab is its tokens and special ids.
    public var Vocab: Vocabulary {
        switch Algorithm {
        case .sentencePiece(let sp): return sp.Vocab
        case .bpe(let b): return b.Vocab
        }
    }

    /// Count is how many tokens there are.
    public var Count: int { return Vocab.Tokens.count }

    /// Encode is text's tokens; with addSpecial, the Bos and Eos the
    /// vocabulary says to add go around them.
    public func Encode(_ text: string, addSpecial: bool = true) -> [int] {
        switch Algorithm {
        case .sentencePiece(let sp): return sp.Encode(text, addSpecial: addSpecial)
        case .bpe(let b): return b.Encode(text, addSpecial: addSpecial)
        }
    }

    /// Decode is the text of ids. With removeSpecial, the Bos and Eos that
    /// encoding added are dropped; with special, control tokens are
    /// written out rather than skipped.
    public func Decode(_ ids: [int], removeSpecial: bool = false, special: bool = false) -> string {
        switch Algorithm {
        case .sentencePiece(let sp): return sp.Decode(ids, removeSpecial: removeSpecial, special: special)
        case .bpe(let b): return b.Decode(ids, removeSpecial: removeSpecial, special: special)
        }
    }
}
