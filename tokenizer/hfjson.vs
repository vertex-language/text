package tokenizer

import "encoding/json"

// The pre-tokenizer regexes of the splits this implements, as
// tokenizer.json files write them.
let llama3Pattern = "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"
let qwen2Pattern = "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"
let gpt2Pattern = "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+"

/// ReadTokenizerJSON is the tokenizer a Hugging Face tokenizer.json holds,
/// with what tokenizer_config.json (when given) says of BOS, EOS and adding
/// them. It reads byte-level BPE -- the tokenizer of GPT-2, Llama 3, Qwen,
/// SmolLM and most models since -- with the pre-tokenizers Split names;
/// anything else is refused, saying what it is.
public func ReadTokenizerJSON(_ bytes: [uint8], config: [uint8]? = nil) throws -> Tokenizer {
    let doc = try json.Parse(bytes: bytes)
    guard let model = doc["model"] else {
        throw ModelError.malformed("tokenizer.json has no model")
    }
    // Older files (GPT-2's) leave the type out of a BPE model.
    let kind = model["type"]?.String ?? (model["merges"] != nil && model["vocab"] != nil ? "BPE" : "?")
    if kind != "BPE" {
        throw ModelError.malformed("a \(kind) tokenizer.json; byte-level BPE is read so far")
    }
    let split = try splitOf(doc["pre_tokenizer"])
    if model["byte_fallback"]?.Bool == true {
        throw ModelError.malformed("a BPE with byte fallback (SentencePiece-style); read its tokenizer.model instead")
    }

    // Tokens by id: the vocabulary, then the added tokens over it.
    guard let vocab = model["vocab"]?.Object else {
        throw ModelError.malformed("tokenizer.json's model has no vocab")
    }
    var count = 0
    for (_, v) in vocab.Members {
        if let id = v.Int { count = max(count, int(id) + 1) }
    }
    let added = doc["added_tokens"]?.Array ?? []
    for a in added {
        if let id = a["id"]?.Int { count = max(count, int(id) + 1) }
    }
    var tokens = [string](repeating: "", count: count)
    var kinds = [Kind](repeating: .Unused, count: count)
    for (text, v) in vocab.Members {
        guard let id = v.Int else { continue }
        tokens[int(id)] = text
        kinds[int(id)] = .Normal
    }
    var byText: [string: int] = [:]
    for a in added {
        guard let id = a["id"]?.Int, let text = a["content"]?.String else { continue }
        tokens[int(id)] = text
        kinds[int(id)] = a["special"]?.Bool == true ? .Control : .UserDefined
    }
    for i in 0..<count {
        byText[tokens[i]] = i
    }

    var merges: [string] = []
    for m in model["merges"]?.Array ?? [] {
        if let s = m.String {
            merges.append(s)
        } else if let pair = m.Array, pair.count == 2, let a = pair[0].String, let b = pair[1].String {
            merges.append(a + " " + b)
        }
    }

    // BOS and EOS, and whether encoding adds BOS: tokenizer_config.json
    // says; else the post-processor's template, if it puts one first.
    var bos: int? = nil
    var eos: int? = nil
    var addBos = false
    var cfg: json.Value? = nil
    if let c = config {
        cfg = try json.Parse(bytes: c)
    }
    func tokenText(_ v: json.Value?) -> string? {
        return v?.String ?? v?["content"]?.String
    }
    if let t = tokenText(cfg?["bos_token"]) { bos = byText[t] }
    if let t = tokenText(cfg?["eos_token"]) { eos = byText[t] }
    if let a = cfg?["add_bos_token"]?.Bool {
        addBos = a
    } else if let first = doc["post_processor"]?["single"]?[0]?["SpecialToken"]?["id"]?.String {
        addBos = true
        if bos == nil { bos = byText[first] }
    } else if let procs = doc["post_processor"]?["processors"]?.Array {
        for p in procs {
            if let first = p["single"]?[0]?["SpecialToken"]?["id"]?.String {
                addBos = true
                if bos == nil { bos = byText[first] }
            }
        }
    }
    var v = Vocabulary(tokens: tokens, scores: [], kinds: kinds, bos: bos, eos: eos, unknown: nil,
                       addBos: addBos, addEos: cfg?["add_eos_token"]?.Bool ?? false, addSpacePrefix: false)
    v.Merges = merges
    return Tokenizer.BPE(v, split: split, ignoreMerges: model["ignore_merges"]?.Bool)
}

// splitOf is the Split a pre_tokenizer is: a ByteLevel with its GPT-2
// regex; a Sequence of Split(regex) and a ByteLevel without one; or
// Digits(individual) then a ByteLevel.
func splitOf(_ pre: json.Value?) throws -> Split {
    guard let p = pre, let kind = p["type"]?.String else {
        throw ModelError.malformed("a tokenizer.json with no pre_tokenizer")
    }
    if kind == "ByteLevel" {
        if p["add_prefix_space"]?.Bool == true {
            throw ModelError.malformed("a ByteLevel pre-tokenizer that adds a prefix space")
        }
        if p["use_regex"]?.Bool == false {
            throw ModelError.malformed("a ByteLevel pre-tokenizer without its regex")
        }
        return .gpt2
    }
    guard kind == "Sequence", let steps = p["pretokenizers"]?.Array, steps.count == 2,
          steps[1]["type"]?.String == "ByteLevel", steps[1]["add_prefix_space"]?.Bool != true else {
        throw ModelError.malformed("a '\(kind)' pre-tokenizer this does not implement: \(json.Encode(p))")
    }
    let first = steps[0]
    if first["type"]?.String == "Digits" && first["individual_digits"]?.Bool == true && steps[1]["use_regex"]?.Bool != false {
        return .digitsThenGPT2
    }
    if first["type"]?.String == "Split", let regex = first["pattern"]?["Regex"]?.String, steps[1]["use_regex"]?.Bool == false {
        switch regex {
        case llama3Pattern: return .llama3
        case qwen2Pattern: return .qwen2
        case gpt2Pattern: return .gpt2
        default: break
        }
        throw ModelError.malformed("a Split pre-tokenizer of a regex this does not implement: \(regex)")
    }
    throw ModelError.malformed("a pre-tokenizer this does not implement: \(json.Encode(p))")
}
