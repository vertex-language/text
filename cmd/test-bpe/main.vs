// text/tokenizer's byte-level BPE against llama.cpp, on its own test
// vocabularies (llama.cpp's models/ggml-vocab-*.gguf, MIT): GPT-2's,
// Llama 3's and Qwen 2's, each input encoded as test-tokenizer-0 expects
// (.out, no specials), and decoded back to the input.
package main

import (
    "fs"
    "model/gguf"
    "text/tokenizer"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

func ids(_ line: Substring) -> [int] {
    return line.split(separator: " ").compactMap { int(String($0)) }
}

let dir = "cmd/test-tokenizer/testdata/"

func inputsOf(_ name: string) throws -> ([string], [Substring]) {
    let raw = try fs.ReadText(fs.Path(dir + "ggml-vocab-\(name).gguf.inp"))
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
    let outs = try fs.ReadText(fs.Path(dir + "ggml-vocab-\(name).gguf.out")).split(separator: "\n", omittingEmptySubsequences: false)
    return (inputs, outs)
}

for (name, split) in [("gpt-2", tokenizer.Split.gpt2), ("llama-bpe", tokenizer.Split.llama3), ("qwen2", tokenizer.Split.qwen2)] {
    let f = try gguf.Open(fs.Path(dir + "ggml-vocab-\(name).gguf"))
    check(f.Text("tokenizer.ggml.model") == "gpt2" && tokenizer.Split.Named(f.Text("tokenizer.ggml.pre") ?? "") == split,
          "\(name): a gpt2 vocabulary whose pre-tokenizer '\(f.Text("tokenizer.ggml.pre") ?? "")' is \(split)")
    let v = tokenizer.Vocabulary(
        tokens: f.Texts("tokenizer.ggml.tokens")!,
        scores: [],
        kinds: f.Integers("tokenizer.ggml.token_type")!.map { tokenizer.Kind(rawValue: $0) ?? .Normal },
        bos: f.Integer("tokenizer.ggml.bos_token_id"),
        eos: f.Integer("tokenizer.ggml.eos_token_id"),
        addBos: f.Flag("tokenizer.ggml.add_bos_token") ?? false,
        addSpacePrefix: false)
    var vocab = v
    vocab.Merges = f.Texts("tokenizer.ggml.merges")!
    let t = tokenizer.Tokenizer.BPE(vocab, split: split)

    let raw = try fs.ReadText(fs.Path(dir + "ggml-vocab-\(name).gguf.inp"))
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
    let outs = try fs.ReadText(fs.Path(dir + "ggml-vocab-\(name).gguf.out")).split(separator: "\n", omittingEmptySubsequences: false)
    var same = 0, back = 0
    for i in 0..<inputs.count {
        let got = t.Encode(inputs[i], addSpecial: false)
        if got == ids(outs[i]) {
            same += 1
        } else {
            let s = inputs[i]
            print("      \(i) '\(s.count > 30 ? String(s.prefix(30)) + "…" : s)': got \(got), want \(ids(outs[i]))")
        }
        if t.Decode(got) == inputs[i] { back += 1 }
    }
    check(same == inputs.count, "\(name): \(same) of \(inputs.count) inputs encoded as llama.cpp's test expects")
    check(back == inputs.count, "\(name): \(back) of \(inputs.count) decoded back to the input")
}
// The same, from the Hugging Face tokenizer.json each vocabulary was
// converted from (testdata/hf/, fetched from the Hub: `hub download
// hf.co/openai-community/gpt2/tokenizer.json`, ...). Llama 3.2's is Llama
// 3's; SmolLM2's has no llama.cpp test of its own, so it is read and
// round-tripped.
for (repo, vocabName, split) in [("gpt2", "gpt-2", tokenizer.Split.gpt2), ("Llama-3.2-1B-Instruct", "llama-bpe", tokenizer.Split.llama3),
                                 ("Qwen2.5-0.5B", "qwen2", tokenizer.Split.qwen2), ("SmolLM2-135M", "", tokenizer.Split.digitsThenGPT2)] {
    let hf = dir + "hf/\(repo)/"
    guard let bytes = try? fs.ReadFile(fs.Path(hf + "tokenizer.json")) else {
        print("skip  \(repo): no testdata/hf/\(repo)/tokenizer.json")
        continue
    }
    do {
        let t = try tokenizer.ReadTokenizerJSON(bytes, config: try? fs.ReadFile(fs.Path(hf + "tokenizer_config.json")))
        guard case .bpe(let b) = t.Algorithm else {
            check(false, "\(repo): a BPE")
            continue
        }
        check(b.Split == split, "\(repo): tokenizer.json's pre-tokenizer is \(split)")
        let (inputs, outs) = try inputsOf(vocabName.isEmpty ? "gpt-2" : vocabName)
        var same = 0, back = 0
        for i in 0..<inputs.count {
            let got = t.Encode(inputs[i], addSpecial: false)
            if !vocabName.isEmpty && got == ids(outs[i]) { same += 1 }
            if t.Decode(got) == inputs[i] { back += 1 }
        }
        if !vocabName.isEmpty {
            check(same == inputs.count, "\(repo): \(same) of \(inputs.count) inputs encoded as llama.cpp's \(vocabName) vocabulary encodes them")
        }
        check(back == inputs.count, "\(repo): \(back) of \(inputs.count) decoded back to the input")
        let v = t.Vocab
        print("      \(repo): \(v.Tokens.count) tokens, \(v.Merges.count) merges, bos \(v.Bos ?? -1) (added: \(v.AddBos)), eos \(v.Eos ?? -1)")
    } catch {
        check(false, "\(repo): \(error)")
    }
}
print(failures == 0 ? "all passed" : "\(failures) failed")
