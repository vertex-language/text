// SentencePiece encoding and decoding, as llama.cpp's llm_tokenizer_spm
// does them (src/llama-vocab.cpp).
package tokenizer

/// The space SentencePiece writes as U+2581, '▁', in its pieces.
let spaceMark: [uint8] = [0xE2, 0x96, 0x81]

/// A symbol of the text being encoded: a run of its bytes, linked to its
/// neighbours, empty once merged into the one before it.
struct Symbol {
    var Start: int
    var Count: int
    var Prev: int
    var Next: int
}

/// A candidate merge of two adjacent symbols into the token they spell.
struct Bigram {
    let Left: int
    let Right: int
    let Score: float32
    let Size: int

    /// Before is the queue's order: the higher score first, and of two
    /// equal scores the one further left.
    func Before(_ o: Bigram) -> bool {
        return Score > o.Score || (Score == o.Score && Left < o.Left)
    }
}

/// A binary heap of bigrams, the best on top.
struct Queue {
    var items: [Bigram] = []

    var IsEmpty: bool { return items.isEmpty }

    mutating func Push(_ b: Bigram) {
        items.append(b)
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if !items[i].Before(items[p]) { break }
            items.swapAt(i, p)
            i = p
        }
    }

    mutating func Pop() -> Bigram {
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1
                let r = l + 1
                var best = i
                if l < items.count && items[l].Before(items[best]) { best = l }
                if r < items.count && items[r].Before(items[best]) { best = r }
                if best == i { break }
                items.swapAt(i, best)
                i = best
            }
        }
        return top
    }
}

/// SentencePiece encodes and decodes with a vocabulary.
public final class SentencePiece {
    public let Vocab: Vocabulary
    let _ids: [string: int]
    let _bytes: [int]

    public init(_ vocab: Vocabulary) {
        self.Vocab = vocab
        var ids: [string: int] = [:]
        for i in 0..<vocab.Tokens.count {
            ids[vocab.Tokens[i]] = i
        }
        self._ids = ids
        // The byte-fallback tokens, <0x00> to <0xFF>.
        var bytes = [int](repeating: -1, count: 256)
        for b in 0..<256 {
            let hex = String(b, radix: 16, uppercase: true)
            if let id = ids["<0x" + (hex.count == 1 ? "0" : "") + hex + ">"] {
                bytes[b] = id
            }
        }
        self._bytes = bytes
    }

    /// Count is how many tokens the vocabulary has.
    public var Count: int { return Vocab.Tokens.count }

    /// Token is the id whose text is exactly text, or nil.
    public func Token(_ text: string) -> int? {
        return _ids[text]
    }

    /// Encode is text's tokens. With addSpecial, the vocabulary's Bos and
    /// Eos go around them as it says to add them. Special tokens written in
    /// the text are text, not tokens.
    public func Encode(_ text: string, addSpecial: bool = true) -> [int] {
        var out: [int] = []
        if addSpecial && Vocab.AddBos, let bos = Vocab.Bos {
            out.append(bos)
        }
        // The dummy prefix, then every space as '▁'.
        var bytes: [uint8] = []
        if Vocab.AddSpacePrefix {
            bytes += spaceMark
        }
        for b in text.utf8 {
            if b == 0x20 {
                bytes += spaceMark
            } else {
                bytes.append(b)
            }
        }
        // Empty text is no fragment at all, so not even the prefix.
        if !text.isEmpty {
            encodePieces(bytes, &out)
        }
        if addSpecial && Vocab.AddEos, let eos = Vocab.Eos {
            out.append(eos)
        }
        return out
    }

    func text(_ bytes: [uint8], _ start: int, _ count: int) -> string {
        return string(decoding: bytes[start..<(start + count)], as: UTF8.self)
    }

    func encodePieces(_ bytes: [uint8], _ out: inout [int]) {
        if bytes.isEmpty {
            return
        }
        // One symbol a UTF-8 character, as its lead byte says.
        var symbols: [Symbol] = []
        var at = 0
        while at < bytes.count {
            let b = bytes[at]
            var n = 1
            if b >= 0xF0 { n = 4 } else if b >= 0xE0 { n = 3 } else if b >= 0xC0 { n = 2 }
            n = min(n, bytes.count - at)
            symbols.append(Symbol(Start: at, Count: n, Prev: symbols.count - 1, Next: at + n == bytes.count ? -1 : symbols.count + 1))
            at += n
        }
        var queue = Queue()
        var merges: [string: (int, int)] = [:]
        func tryBigram(_ left: int, _ right: int) {
            if left == -1 || right == -1 {
                return
            }
            let t = text(bytes, symbols[left].Start, symbols[left].Count + symbols[right].Count)
            guard let id = _ids[t] else {
                return
            }
            queue.Push(Bigram(Left: left, Right: right, Score: Vocab.Scores[id], Size: symbols[left].Count + symbols[right].Count))
            merges[t] = (left, right)
        }
        for i in 1..<max(1, symbols.count) {
            tryBigram(i - 1, i)
        }
        // Merge the best pair while there is one; a pair whose symbols
        // changed since it was queued is stale and skipped.
        while !queue.IsEmpty {
            let b = queue.Pop()
            if symbols[b.Left].Count == 0 || symbols[b.Right].Count == 0 ||
                symbols[b.Left].Count + symbols[b.Right].Count != b.Size {
                continue
            }
            symbols[b.Left].Count += symbols[b.Right].Count
            symbols[b.Right].Count = 0
            symbols[b.Left].Next = symbols[b.Right].Next
            if symbols[b.Right].Next >= 0 {
                symbols[symbols[b.Right].Next].Prev = b.Left
            }
            tryBigram(symbols[b.Left].Prev, b.Left)
            tryBigram(b.Left, symbols[b.Left].Next)
        }
        // Each remaining symbol is a token, or the two it was merged from,
        // or, as a last resort, its bytes.
        var i = 0
        while i != -1 {
            resegment(bytes, symbols, merges, symbols[i], &out)
            i = symbols[i].Next
        }
    }

    func resegment(_ bytes: [uint8], _ symbols: [Symbol], _ merges: [string: (int, int)], _ s: Symbol, _ out: inout [int]) {
        let t = text(bytes, s.Start, s.Count)
        if let id = _ids[t] {
            out.append(id)
            return
        }
        guard let m = merges[t] else {
            for j in 0..<s.Count {
                let id = _bytes[int(bytes[s.Start + j])]
                out.append(id >= 0 ? id : (Vocab.Unknown ?? 0))
            }
            return
        }
        resegment(bytes, symbols, merges, symbols[m.0], &out)
        resegment(bytes, symbols, merges, symbols[m.1], &out)
    }

    /// Piece is a token's bytes as text: '▁' a space, a byte token its
    /// byte. A control or unknown token is nothing unless special, and then
    /// its text. Bytes, since one character may take several byte tokens.
    public func Piece(_ id: int, special: bool = false) -> [uint8] {
        if id < 0 || id >= Count {
            return []
        }
        let kind = Vocab.Kinds[id]
        let t = Vocab.Tokens[id]
        switch kind {
        case .Control, .Unknown:
            return special ? Array(t.utf8) : []
        case .UserDefined:
            return Array(t.utf8)
        case .Normal:
            var out: [uint8] = []
            let b = Array(t.utf8)
            var i = 0
            while i < b.count {
                if i + 2 < b.count && b[i] == 0xE2 && b[i + 1] == 0x96 && b[i + 2] == 0x81 {
                    out.append(0x20)
                    i += 3
                } else {
                    out.append(b[i])
                    i += 1
                }
            }
            return out
        case .Byte:
            // "<0xXX>"
            let h = Array(t.utf8)
            if h.count == 6 {
                return [uint8(hexValue(h[3]) * 16 + hexValue(h[4]))]
            }
            return []
        case .Unused:
            return []
        }
    }

    /// Decode is the text of tokens, as llama.cpp's llama_detokenize makes
    /// it: the dummy prefix's space is taken off the first piece, and with
    /// removeSpecial a leading Bos (and trailing Eos) that encoding added
    /// are dropped.
    public func Decode(_ ids: [int], removeSpecial: bool = false, special: bool = false) -> string {
        var ids = ids
        var strip = Vocab.AddSpacePrefix
        if removeSpecial && Vocab.AddBos && !ids.isEmpty && ids[0] == Vocab.Bos {
            strip = false
            ids.removeFirst()
        }
        if removeSpecial && Vocab.AddEos && !ids.isEmpty && ids[ids.count - 1] == Vocab.Eos {
            ids.removeLast()
        }
        var out: [uint8] = []
        for id in ids {
            var p = Piece(id, special: special)
            if strip && !p.isEmpty && p[0] == 0x20 {
                p.removeFirst()
            }
            // llama.cpp spends the strip on the first token, even one that
            // makes nothing.
            strip = false
            out += p
        }
        return string(decoding: out, as: UTF8.self)
    }
}

func hexValue(_ c: uint8) -> int {
    if c >= 0x30 && c <= 0x39 { return int(c) - 0x30 }
    if c >= 0x41 && c <= 0x46 { return int(c) - 0x41 + 10 }
    if c >= 0x61 && c <= 0x66 { return int(c) - 0x61 + 10 }
    return 0
}
