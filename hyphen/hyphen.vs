// Package hyphen says where a word may break with a hyphen, by a language's
// dictionary: what CSS's hyphens: auto wants.
//
// macOS: the system's dictionaries. Elsewhere there are none yet, and every
// word stays whole.
package hyphen

/// The byte offsets a word may break at, in order, for a language tag such
/// as "en" or "de-AT". Empty where there's no dictionary for it.
public func Points(word: string, lang: string) -> [int] {
    var found = [int32](repeating: 0, count: 64)
    let n = found.withUnsafeMutableBufferPointer { p in hyphenPoints(word, lang, p.baseAddress, 64) }
    var out: [int] = []
    var i = 0
    while i < int(n) {
        out.append(int(found[i]))
        i += 1
    }
    return out
}
