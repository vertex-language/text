package tokenizer

/// Split is how text is cut into words before byte-level BPE merges
/// within each: the pre-tokenizer regex of the model's tokenizer.json,
/// as llama.cpp implements each by hand (src/unicode.cpp).
public enum Split: Equatable {
    /// GPT-2's: 's|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)
    /// (GPT-2, OLMo, MPT, …).
    case gpt2
    /// GPT-2's after each digit is cut off alone (\p{N} first): SmolLM,
    /// StarCoder, Command R, ….
    case digitsThenGPT2
    /// Llama 3's: case-insensitive contractions, [^\r\n\p{L}\p{N}]?\p{L}+,
    /// \p{N}{1,3}, ?[^\s\p{L}\p{N}]+[\r\n]*, \s*[\r\n]+, \s+(?!\S), \s+.
    case llama3
    /// Qwen 2's: Llama 3's with one digit at a time.
    case qwen2

    /// Named is the Split for a GGUF tokenizer.ggml.pre, or nil for one this
    /// does not implement.
    public static func Named(_ pre: string) -> Split? {
        switch pre {
        case "default", "gpt-2", "gpt2", "mpt", "olmo", "jais", "trillion", "granite-docling":
            return .gpt2
        case "smollm", "starcoder", "refact", "command-r", "codeshell", "exaone", "minerva-7b":
            return .digitsThenGPT2
        case "llama3", "llama-v3", "llama-bpe", "falcon3", "pixtral", "dbrx", "smaug-bpe":
            return .llama3
        case "qwen2", "stablelm2", "hunyuan", "solar-open":
            return .qwen2
        default:
            return nil
        }
    }
}

/// BPE is byte-level byte-pair encoding, GPT-2's: text cut into words by
/// its Split, each word's bytes spelled as printable characters (GPT-2's
/// bytes_to_unicode), then merged pairwise, the lowest-ranked merge first,
/// into the vocabulary's tokens. It is llama.cpp's llm_tokenizer_bpe, rule
/// for rule, for the splits it names.
public final class BPE {
    public let Vocab: Vocabulary
    public let Split: Split
    /// IgnoreMerges takes a word that is a token whole, without merging:
    /// Llama 3's tokenizer.json "ignore_merges".
    public let IgnoreMerges: bool
    let _ids: [string: int]
    let _ranks: [string: int]
    // Each byte's printable character, as a string; and back.
    let _byteChars: [string]
    let _charBytes: [string: uint8]
    // Tokens encoding splits out whole before any word is cut: those the
    // vocabulary marks UserDefined (llama.cpp does so without parse_special).
    let _userDefined: [(string, int)]

    public init(_ vocab: Vocabulary, split: Split, ignoreMerges: bool? = nil) {
        self.Vocab = vocab
        self.Split = split
        // llama.cpp sets it for Llama 3's pre-tokenizer, whose
        // tokenizer.json has it.
        self.IgnoreMerges = ignoreMerges ?? (split == .llama3)
        var ids: [string: int] = [:]
        for i in 0..<vocab.Tokens.count {
            ids[vocab.Tokens[i]] = i
        }
        self._ids = ids
        var ranks: [string: int] = [:]
        for i in 0..<vocab.Merges.count {
            if ranks[vocab.Merges[i]] == nil {
                ranks[vocab.Merges[i]] = i
            }
        }
        self._ranks = ranks
        var chars: [string] = []
        var back: [string: uint8] = [:]
        var extra: uint32 = 0
        for b in 0..<256 {
            var cp = uint32(b)
            if !((b >= 0x21 && b <= 0x7E) || (b >= 0xA1 && b <= 0xAC) || (b >= 0xAE && b <= 0xFF)) {
                cp = 256 + extra
                extra += 1
            }
            var u: [uint8] = []
            appendUTF8(&u, cp)
            let s = String(decoding: u, as: UTF8.self)
            chars.append(s)
            back[s] = uint8(b)
        }
        self._byteChars = chars
        self._charBytes = back
        var user: [(string, int)] = []
        for i in 0..<vocab.Tokens.count where vocab.Kinds[i] == .UserDefined && !vocab.Tokens[i].isEmpty {
            user.append((vocab.Tokens[i], i))
        }
        // Longest first, as llama.cpp tries them.
        self._userDefined = user.sorted { $0.0.utf8.count > $1.0.utf8.count }
    }

    public var Count: int { return Vocab.Tokens.count }

    /// Encode is text's tokens; with addSpecial, the Bos and Eos the
    /// vocabulary says to add go around them.
    public func Encode(_ text: string, addSpecial: bool = true) -> [int] {
        var out: [int] = []
        if addSpecial && Vocab.AddBos, let bos = Vocab.Bos {
            out.append(bos)
        }
        for (piece, special) in partition(text) {
            if let id = special {
                out.append(id)
            } else {
                encodeText(piece, &out)
            }
        }
        if addSpecial && Vocab.AddEos, let eos = Vocab.Eos {
            out.append(eos)
        }
        return out
    }

    // partition cuts text around the user-defined tokens it holds.
    func partition(_ text: string) -> [(string, int?)] {
        if _userDefined.isEmpty {
            return [(text, nil)]
        }
        let b = [uint8](text.utf8)
        var out: [(string, int?)] = []
        var start = 0
        var i = 0
        while i < b.count {
            var matched = false
            for (tok, id) in _userDefined {
                let t = [uint8](tok.utf8)
                if i + t.count <= b.count && Array(b[i..<(i + t.count)]) == t {
                    if i > start {
                        out.append((String(decoding: b[start..<i], as: UTF8.self), nil))
                    }
                    out.append((tok, id))
                    i += t.count
                    start = i
                    matched = true
                    break
                }
            }
            if !matched {
                i += 1
            }
        }
        if start < b.count {
            out.append((String(decoding: b[start..<b.count], as: UTF8.self), nil))
        }
        return out
    }

    func encodeText(_ text: string, _ out: inout [int]) {
        let cpts = codepoints(text)
        var words = [cpts.count]
        if Split == .digitsThenGPT2 {
            words = splitDigits(cpts, words)
        }
        switch Split {
        case .gpt2, .digitsThenGPT2:
            words = splitGPT2(cpts, words)
        case .llama3:
            words = splitLlama3(cpts, words, maxDigits: 3)
        case .qwen2:
            words = splitLlama3(cpts, words, maxDigits: 1)
        }
        var at = 0
        for n in words {
            var bytes: [uint8] = []
            for k in at..<(at + n) {
                appendUTF8(&bytes, cpts[k])
            }
            at += n
            var chars: [string] = []
            for byte in bytes {
                chars.append(_byteChars[int(byte)])
            }
            if IgnoreMerges, let id = _ids[chars.joined()] {
                out.append(id)
                continue
            }
            merge(chars, &out)
        }
    }

    // merge runs BPE over one word's characters and appends its tokens:
    // the lowest-ranked adjacent pair merged first, the leftmost of equals.
    func merge(_ chars: [string], _ out: inout [int]) {
        var symbols = chars
        while symbols.count > 1 {
            var best = -1
            var bestRank = int.max
            for i in 0..<(symbols.count - 1) {
                if let r = _ranks[symbols[i] + " " + symbols[i + 1]], r < bestRank {
                    bestRank = r
                    best = i
                }
            }
            if best < 0 {
                break
            }
            symbols[best] = symbols[best] + symbols[best + 1]
            symbols.remove(at: best + 1)
        }
        for s in symbols {
            if let id = _ids[s] {
                out.append(id)
            } else {
                // Not a token: its characters one by one, each a byte's.
                for c in s {
                    if let id = _ids[String(c)] {
                        out.append(id)
                    }
                }
            }
        }
    }

    /// Decode is the text of ids: each token's characters taken back to
    /// the bytes they spell. With removeSpecial, the Bos and Eos encoding
    /// added are dropped; control tokens are skipped unless special.
    public func Decode(_ ids: [int], removeSpecial: bool = false, special: bool = false) -> string {
        var ids = ids
        if removeSpecial && Vocab.AddBos && !ids.isEmpty && ids[0] == Vocab.Bos {
            ids.removeFirst()
        }
        if removeSpecial && Vocab.AddEos && !ids.isEmpty && ids[ids.count - 1] == Vocab.Eos {
            ids.removeLast()
        }
        var bytes: [uint8] = []
        for id in ids {
            if id < 0 || id >= Vocab.Tokens.count {
                continue
            }
            let text = Vocab.Tokens[id]
            switch Vocab.Kinds[id] {
            case .Control, .Unknown, .Unused:
                if special {
                    bytes.append(contentsOf: text.utf8)
                }
            case .UserDefined:
                bytes.append(contentsOf: text.utf8)
            default:
                for c in text {
                    if let b = _charBytes[String(c)] {
                        bytes.append(b)
                    } else {
                        bytes.append(contentsOf: String(c).utf8)
                    }
                }
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

// ---- splitting, as llama.cpp's unicode_regex_split_custom_* ----

let outOfRange: uint32 = 0xFFFFFFFF
let flagNumber: uint32 = 0x0002
let flagLetter: uint32 = 0x0004
let flagWhitespace: uint32 = 0x0100

// flagsOf is a codepoint's category flags, with \s's whitespace bit.
func flagsOf(_ cp: uint32) -> uint32 {
    var lo = 0
    var hi = flagRanges.count / 2 - 1
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if flagRanges[2 * mid] <= cp {
            lo = mid
        } else {
            hi = mid - 1
        }
    }
    var f = flagRanges[2 * lo + 1]
    if isWhitespace(cp) {
        f |= flagWhitespace
    }
    return f
}

func isWhitespace(_ cp: uint32) -> bool {
    for w in whitespaceSet where w == cp {
        return true
    }
    return false
}

func codepoints(_ s: string) -> [uint32] {
    var out: [uint32] = []
    for u in s.unicodeScalars {
        out.append(u.value)
    }
    return out
}

func appendUTF8(_ out: inout [uint8], _ cp: uint32) {
    if cp < 0x80 {
        out.append(uint8(cp))
    } else if cp < 0x800 {
        out.append(uint8(0xC0 | (cp >> 6)))
        out.append(uint8(0x80 | (cp & 0x3F)))
    } else if cp < 0x10000 {
        out.append(uint8(0xE0 | (cp >> 12)))
        out.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
        out.append(uint8(0x80 | (cp & 0x3F)))
    } else {
        out.append(uint8(0xF0 | (cp >> 18)))
        out.append(uint8(0x80 | ((cp >> 12) & 0x3F)))
        out.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
        out.append(uint8(0x80 | (cp & 0x3F)))
    }
}

func asciiLower(_ c: uint32) -> uint32 {
    return c >= 0x41 && c <= 0x5A ? c + 32 : c
}

// splitter is one pass over the words so far: the cursor and the lengths
// of the words it cuts, as the C++ closures keep them.
struct splitter {
    let cpts: [uint32]
    var ini: int = 0
    var end: int = 0
    var prevEnd: int = 0
    var out: [int] = []

    init(_ cpts: [uint32]) {
        self.cpts = cpts
    }

    func cpt(_ pos: int) -> uint32 {
        return pos >= ini && pos < end ? cpts[pos] : outOfRange
    }

    func flags(_ pos: int) -> uint32 {
        return pos >= ini && pos < end ? flagsOf(cpts[pos]) : 0
    }

    mutating func add(_ at: int) -> int {
        let n = at - prevEnd
        if n > 0 {
            out.append(n)
        }
        prevEnd = at
        return n
    }
}

// splitDigits isolates each \p{N} codepoint, keeping what lies between.
func splitDigits(_ cpts: [uint32], _ words: [int]) -> [int] {
    var out: [int] = []
    var start = 0
    for w in words {
        var run = 0
        for pos in start..<(start + w) {
            if flagsOf(cpts[pos]) & flagNumber != 0 {
                if run > 0 { out.append(run) }
                out.append(1)
                run = 0
            } else {
                run += 1
            }
        }
        if run > 0 { out.append(run) }
        start += w
    }
    return out
}

func splitGPT2(_ cpts: [uint32], _ words: [int]) -> [int] {
    var s = splitter(cpts)
    var start = 0
    for w in words {
        s.ini = start
        s.end = start + w
        s.prevEnd = start
        start += w
        var pos = s.ini
        while pos < s.end {
            let c = s.cpt(pos)
            let f = s.flags(pos)
            // 's|'t|'re|'ve|'m|'ll|'d
            if c == 0x27 && pos + 1 < s.end {
                let n = s.cpt(pos + 1)
                if n == 0x73 || n == 0x74 || n == 0x6D || n == 0x64 {
                    pos += s.add(pos + 2)
                    continue
                }
                if pos + 2 < s.end {
                    let nn = s.cpt(pos + 2)
                    if (n == 0x72 && nn == 0x65) || (n == 0x76 && nn == 0x65) || (n == 0x6C && nn == 0x6C) {
                        pos += s.add(pos + 3)
                        continue
                    }
                }
            }
            var f2 = c == 0x20 ? s.flags(pos + 1) : f
            // <space>?\p{L}+
            if f2 & flagLetter != 0 {
                if c == 0x20 { pos += 1 }
                while f2 & flagLetter != 0 {
                    pos += 1
                    f2 = s.flags(pos)
                }
                _ = s.add(pos)
                continue
            }
            // <space>?\p{N}+
            if f2 & flagNumber != 0 {
                if c == 0x20 { pos += 1 }
                while f2 & flagNumber != 0 {
                    pos += 1
                    f2 = s.flags(pos)
                }
                _ = s.add(pos)
                continue
            }
            // <space>?[^\s\p{L}\p{N}]+
            if f2 & (flagWhitespace | flagLetter | flagNumber) == 0 && f2 != 0 {
                if c == 0x20 { pos += 1 }
                while f2 & (flagWhitespace | flagLetter | flagNumber) == 0 && f2 != 0 {
                    pos += 1
                    f2 = s.flags(pos)
                }
                _ = s.add(pos)
                continue
            }
            var spaces = 0
            while s.flags(pos + spaces) & flagWhitespace != 0 {
                spaces += 1
            }
            // \s+(?!\S)
            if spaces > 1 && s.cpt(pos + spaces) != outOfRange {
                pos += spaces - 1
                _ = s.add(pos)
                continue
            }
            // \s+
            if spaces > 0 {
                pos += spaces
                _ = s.add(pos)
                continue
            }
            pos += 1
            _ = s.add(pos)
        }
    }
    return s.out
}

func splitLlama3(_ cpts: [uint32], _ words: [int], maxDigits: int) -> [int] {
    var s = splitter(cpts)
    var start = 0
    for w in words {
        s.ini = start
        s.end = start + w
        s.prevEnd = start
        start += w
        var pos = s.ini
        while pos < s.end {
            let c = s.cpt(pos)
            let f = s.flags(pos)
            // (?i:'s|'t|'re|'ve|'m|'ll|'d)
            if c == 0x27 && pos + 1 < s.end {
                let n = asciiLower(s.cpt(pos + 1))
                if n == 0x73 || n == 0x74 || n == 0x6D || n == 0x64 {
                    pos += s.add(pos + 2)
                    continue
                }
                if pos + 2 < s.end {
                    let nn = asciiLower(s.cpt(pos + 2))
                    if (n == 0x72 && nn == 0x65) || (n == 0x76 && nn == 0x65) || (n == 0x6C && nn == 0x6C) {
                        pos += s.add(pos + 3)
                        continue
                    }
                }
            }
            // [^\r\n\p{L}\p{N}]?\p{L}+
            if !(c == 0x0D || c == 0x0A || f & flagNumber != 0) {
                if f & flagLetter != 0 || s.flags(pos + 1) & flagLetter != 0 {
                    pos += 1
                    while s.flags(pos) & flagLetter != 0 {
                        pos += 1
                    }
                    _ = s.add(pos)
                    continue
                }
            }
            // \p{N}{1,maxDigits}
            if f & flagNumber != 0 {
                var ini = pos
                while s.flags(pos) & flagNumber != 0 {
                    pos += 1
                    if pos - ini >= maxDigits {
                        _ = s.add(pos)
                        ini = pos
                    }
                }
                _ = s.add(pos)
                continue
            }
            // <space>?[^\s\p{L}\p{N}]+[\r\n]*
            var f2 = c == 0x20 ? s.flags(pos + 1) : f
            if f2 & (flagWhitespace | flagLetter | flagNumber) == 0 && f != 0 {
                if c == 0x20 { pos += 1 }
                while f2 & (flagWhitespace | flagLetter | flagNumber) == 0 && f2 != 0 {
                    pos += 1
                    f2 = s.flags(pos)
                }
                var c2 = s.cpt(pos)
                while c2 == 0x0D || c2 == 0x0A {
                    pos += 1
                    c2 = s.cpt(pos)
                }
                _ = s.add(pos)
                continue
            }
            var spaces = 0
            var lastRN = 0
            while s.flags(pos + spaces) & flagWhitespace != 0 {
                let c2 = s.cpt(pos + spaces)
                if c2 == 0x0D || c2 == 0x0A {
                    lastRN = pos + spaces + 1
                }
                spaces += 1
            }
            // \s*[\r\n]+
            if lastRN > 0 {
                pos = lastRN
                _ = s.add(pos)
                continue
            }
            // \s+(?!\S)
            if spaces > 1 && s.cpt(pos + spaces) != outOfRange {
                pos += spaces - 1
                _ = s.add(pos)
                continue
            }
            // \s+
            if spaces > 0 {
                pos += spaces
                _ = s.add(pos)
                continue
            }
            pos += 1
            _ = s.add(pos)
        }
    }
    return s.out
}
