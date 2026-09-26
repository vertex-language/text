package tokenizer

/// ModelError is a tokenizer file that could not be read, and why.
public enum ModelError: Error, CustomStringConvertible {
    case malformed(string)

    public var description: string {
        switch self {
        case .malformed(let why): return "tokenizer: " + why
        }
    }
}

/// ReadSentencePieceModel is the vocabulary in a SentencePiece model file
/// (tokenizer.model: a ModelProto, protobuf): each piece's text, score and
/// type, the unknown, BOS and EOS ids from its trainer spec, and whether
/// its normalizer adds the dummy prefix. Adding BOS and EOS is not in the
/// file; the defaults are Llama's (BOS, no EOS), and a caller with a
/// tokenizer_config.json sets them from it.
public func ReadSentencePieceModel(_ bytes: [uint8]) throws -> Vocabulary {
    var tokens: [string] = []
    var scores: [float32] = []
    var kinds: [Kind] = []
    // trainer_spec defaults (sentencepiece_model.proto).
    var unk = 0
    var bos = 1
    var eos = 2
    var dummyPrefix = true
    var r = protoReader(bytes, 0, bytes.count)
    while let (field, wire) = try r.key() {
        switch (field, wire) {
        case (1, 2): // repeated SentencePiece pieces
            var p = try r.sub()
            var piece = ""
            var score: float32 = 0
            var kind = Kind.Normal
            while let (f, w) = try p.key() {
                switch (f, w) {
                case (1, 2): piece = try p.text()
                case (2, 5): score = try p.float()
                case (3, 0): kind = Kind(rawValue: int(try p.varint())) ?? .Normal
                default: try p.skip(w)
                }
            }
            tokens.append(piece)
            scores.append(score)
            kinds.append(kind)
        case (2, 2): // trainer_spec
            var t = try r.sub()
            while let (f, w) = try t.key() {
                switch (f, w) {
                case (40, 0): unk = int(int32(truncatingIfNeeded: try t.varint()))
                case (41, 0): bos = int(int32(truncatingIfNeeded: try t.varint()))
                case (42, 0): eos = int(int32(truncatingIfNeeded: try t.varint()))
                default: try t.skip(w)
                }
            }
        case (3, 2): // normalizer_spec
            var n = try r.sub()
            while let (f, w) = try n.key() {
                if f == 3 && w == 0 {
                    dummyPrefix = try n.varint() != 0
                } else {
                    try n.skip(w)
                }
            }
        default:
            try r.skip(wire)
        }
    }
    if tokens.isEmpty {
        throw ModelError.malformed("a SentencePiece model with no pieces")
    }
    func id(_ i: int) -> int? {
        return i >= 0 && i < tokens.count ? i : nil
    }
    return Vocabulary(tokens: tokens, scores: scores, kinds: kinds, bos: id(bos), eos: id(eos), unknown: id(unk),
                      addBos: true, addEos: false, addSpacePrefix: dummyPrefix)
}

// protoReader reads protobuf's wire format over bytes[at..<end].
struct protoReader {
    let b: [uint8]
    var at: int
    let end: int

    init(_ b: [uint8], _ at: int, _ end: int) {
        self.b = b
        self.at = at
        self.end = end
    }

    mutating func varint() throws -> uint64 {
        var v: uint64 = 0
        var shift: uint64 = 0
        while true {
            if at >= end || shift > 63 {
                throw ModelError.malformed("a truncated varint")
            }
            let c = b[at]
            at += 1
            v |= uint64(c & 0x7F) << shift
            if c & 0x80 == 0 {
                return v
            }
            shift += 7
        }
    }

    // key is the next field number and wire type, or nil at the end.
    mutating func key() throws -> (int, int)? {
        if at >= end {
            return nil
        }
        let k = try varint()
        return (int(k >> 3), int(k & 7))
    }

    mutating func length() throws -> int {
        let n = try varint()
        if n > uint64(end - at) {
            throw ModelError.malformed("a field of \(n) bytes runs past its message")
        }
        return int(n)
    }

    mutating func sub() throws -> protoReader {
        let n = try length()
        let r = protoReader(b, at, at + n)
        at += n
        return r
    }

    mutating func text() throws -> string {
        let n = try length()
        let s = String(decoding: b[at..<(at + n)], as: UTF8.self)
        at += n
        return s
    }

    mutating func float() throws -> float32 {
        if end - at < 4 {
            throw ModelError.malformed("a truncated float")
        }
        let bits = uint32(b[at]) | uint32(b[at + 1]) << 8 | uint32(b[at + 2]) << 16 | uint32(b[at + 3]) << 24
        at += 4
        return float32(bitPattern: bits)
    }

    mutating func skip(_ wire: int) throws {
        switch wire {
        case 0: _ = try varint()
        case 1: at += 8
        case 2:
            let n = try length()
            at += n
        case 5: at += 4
        default: throw ModelError.malformed("wire type \(wire)")
        }
        if at > end {
            throw ModelError.malformed("a field runs past its message")
        }
    }
}
