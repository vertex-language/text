// text/tokenizer against llama.cpp, on Llama 2's SentencePiece vocabulary
// (llama.cpp's own test vocabulary, models/ggml-vocab-llama-spm.gguf, MIT):
// its 46 inputs encoded as llama.cpp's test-tokenizer-0 expects (.out, no
// specials), and encoded with specials and decoded both ways as its
// libllama does (golden/, from oracle/tokenize_dump.cpp).
package main

import "fs"
import "model/gguf"
import "text/tokenizer"

var failures = 0

func check(_ ok: bool, _ what: string) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

func vocabulary(_ f: gguf.File) -> tokenizer.Vocabulary {
    let kinds = f.Integers("tokenizer.ggml.token_type")!.map { tokenizer.Kind(rawValue: $0) ?? .Normal }
    return tokenizer.Vocabulary(
        tokens: f.Texts("tokenizer.ggml.tokens")!,
        scores: f.Numbers("tokenizer.ggml.scores")!.map { float32($0) },
        kinds: kinds,
        bos: f.Integer("tokenizer.ggml.bos_token_id"),
        eos: f.Integer("tokenizer.ggml.eos_token_id"),
        unknown: f.Integer("tokenizer.ggml.unknown_token_id"),
        addBos: f.Flag("tokenizer.ggml.add_bos_token") ?? true,
        addEos: f.Flag("tokenizer.ggml.add_eos_token") ?? false,
        addSpacePrefix: f.Flag("tokenizer.ggml.add_space_prefix") ?? true)
}

func hex(_ s: string) -> string {
    let digits = Array("0123456789abcdef".utf8)
    var out: [uint8] = []
    for b in s.utf8 {
        out.append(digits[int(b >> 4)])
        out.append(digits[int(b & 15)])
    }
    return string(decoding: out, as: UTF8.self)
}

func ids(_ line: Substring) -> [int] {
    return line.split(separator: " ").compactMap { int(String($0)) }
}

let dir = "tests/tokenizer/"
let name = "ggml-vocab-llama-spm.gguf"
let sp = tokenizer.SentencePiece(vocabulary(try gguf.Open(fs.Path(dir + "testdata/" + name))))
check(sp.Count == 32000 && sp.Token("<s>") == 1 && sp.Token("<0x0A>") == 13, "the vocabulary: 32000 tokens, <s> and a byte token found")

let raw = try fs.ReadText(fs.Path(dir + "testdata/" + name + ".inp"))
// Inputs are separated by a line "__ggml_vocab_test__", and may hold
// newlines themselves.
var inputs: [string] = []
var group: [string] = []
for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
    if line == "__ggml_vocab_test__" {
        inputs.append(group.joined(separator: "\n"))
        group = []
    } else {
        group.append(String(line))
    }
}
// After the last separator, nothing is an input, as llama.cpp reads it.
let last = group.joined(separator: "\n")
if !last.isEmpty {
    inputs.append(last)
}
let outs = try fs.ReadText(fs.Path(dir + "testdata/" + name + ".out")).split(separator: "\n", omittingEmptySubsequences: false)
let golden = try fs.ReadText(fs.Path(dir + "golden/ggml-vocab-llama-spm.txt")).split(separator: "\n")
check(inputs.count == 46 && golden.count == 3 * inputs.count, "46 inputs, each with its expectations")

var plain = 0, special = 0, decoded = 0
for i in 0..<inputs.count {
    let s = inputs[i]
    let show = s.count > 24 ? String(s.prefix(24)) + "…" : s
    let got = sp.Encode(s, addSpecial: false)
    if got == ids(outs[i]) { plain += 1 } else { print("      \(i) '\(show)': got \(got), want \(ids(outs[i]))") }
    let enc = sp.Encode(s)
    if enc == ids(golden[3 * i].dropFirst(4)) { special += 1 } else { print("      \(i) with specials: got \(enc)") }
    let dec = hex(sp.Decode(enc)), decr = hex(sp.Decode(enc, removeSpecial: true))
    if "dec " + dec == golden[3 * i + 1] && "decr " + decr == golden[3 * i + 2] { decoded += 1 } else {
        print("      \(i) '\(show)' decoded: \(dec) / \(decr)")
    }
}
check(plain == inputs.count, "Encode, no specials: \(plain) of \(inputs.count) as llama.cpp's test expects")
check(special == inputs.count, "Encode with <s>: \(special) of \(inputs.count) as libllama")
check(decoded == inputs.count, "Decode, keeping and removing specials: \(decoded) of \(inputs.count) as libllama")
check(sp.Decode(sp.Encode("héllo wörld 👋\n"), removeSpecial: true) == " héllo wörld 👋\n", "an emoji through byte tokens and back")
check(sp.Encode("") == [1] && sp.Encode("", addSpecial: false) == [], "empty text: only <s>, or nothing")
print(failures == 0 ? "all passed" : "\(failures) failed")
