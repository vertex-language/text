// The oracle for text/tokenizer: llama.cpp's own tokenizer (libllama, the
// vocabulary only) over each input of a .inp file -- encoded with the
// specials added, and that decoded with and without removing them, bytes
// in hex -- one line each:
//
//   c++ -std=c++17 -I$LLAMA/include -I$LLAMA/ggml/include tokenize_dump.cpp -L$LLAMA/build/bin -lllama -o tokenize_dump
//   ./tokenize_dump vocab.gguf vocab.gguf.inp > golden/vocab.txt
#include "llama.h"
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

static std::string hex(const std::string& s) {
    static const char* d = "0123456789abcdef";
    std::string out;
    for (unsigned char c : s) { out += d[c >> 4]; out += d[c & 15]; }
    return out;
}

static std::string detok(const llama_vocab* v, const std::vector<llama_token>& t, bool remove_special) {
    std::string s(t.size() * 16 + 16, '\0');
    int n = llama_detokenize(v, t.data(), (int)t.size(), &s[0], (int)s.size(), remove_special, false);
    s.resize(n < 0 ? 0 : n);
    return s;
}

int main(int argc, char** argv) {
    if (argc != 3) { fprintf(stderr, "usage: tokenize_dump vocab.gguf inputs.inp\n"); return 2; }
    llama_log_set([](ggml_log_level, const char*, void*) {}, nullptr);
    llama_backend_init();
    llama_model_params mp = llama_model_default_params();
    mp.vocab_only = true;
    llama_model* m = llama_model_load_from_file(argv[1], mp);
    if (!m) { fprintf(stderr, "cannot load %s\n", argv[1]); return 1; }
    const llama_vocab* v = llama_model_get_vocab(m);
    std::ifstream f(argv[2], std::ios::binary);
    std::stringstream ss; ss << f.rdbuf();
    std::string raw = ss.str(), sep = "\n__ggml_vocab_test__\n";
    std::vector<std::string> inputs;
    for (size_t pos = 0; pos < raw.size();) {
        size_t next = raw.find(sep, pos);
        if (next == std::string::npos) { inputs.push_back(raw.substr(pos)); break; }
        inputs.push_back(raw.substr(pos, next - pos));
        pos = next + sep.size();
    }
    for (const std::string& in : inputs) {
        std::vector<llama_token> t(in.size() + 8);
        int n = llama_tokenize(v, in.data(), (int)in.size(), t.data(), (int)t.size(), true, false);
        t.resize(n < 0 ? 0 : n);
        printf("enc");
        for (llama_token id : t) printf(" %d", id);
        printf("\ndec %s\ndecr %s\n", hex(detok(v, t, false)).c_str(), hex(detok(v, t, true)).c_str());
    }
    llama_model_free(m);
    return 0;
}
