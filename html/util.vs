package html

func bytesFromString(_ text: string) -> [uint8] {
    var out: [uint8] = []
    for b in text.utf8 {
        out.append(b)
    }
    return out
}

func stringFromBytes(_ bytes: [uint8], from start: int, to end: int) -> string {
    if start >= end { return "" }
    var chars: [CChar] = []
    var i = start
    while i < end {
        chars.append(CChar(truncatingIfNeeded: bytes[i]))
        i += 1
    }
    chars.append(0)
    return string(cString: chars)
}

func toLower(_ s: string) -> string {
    var b: [uint8] = []
    for byte in s.utf8 {
        if byte >= 65 && byte <= 90 { // 'A'...'Z'
            b.append(byte + 32)
        } else {
            b.append(byte)
        }
    }
    return stringFromBytes(b, from: 0, to: b.count)
}

func isWhitespace(_ b: uint8) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13 || b == 12 // space, tab, LF, CR, FF
}

func isTagChar(_ b: uint8) -> bool {
    return (b >= 97 && b <= 122) || // 'a'...'z'
           (b >= 65 && b <= 90) ||  // 'A'...'Z'
           (b >= 48 && b <= 57) ||  // '0'...'9'
           b == 45 || b == 95 || b == 58 // '-', '_', ':'
}

func isVoidElement(_ tag: string) -> bool {
    let lower = toLower(tag)
    return lower == "area" || lower == "base" || lower == "br" || lower == "col" ||
           lower == "embed" || lower == "hr" || lower == "img" || lower == "input" ||
           lower == "link" || lower == "meta" || lower == "source" || lower == "track" ||
           lower == "wbr"
}

func isRawTextElement(_ tag: string) -> bool {
    return tag == "script" || tag == "style" || tag == "textarea" || tag == "title"
}

// The raw text elements whose text still has character references:
// RCDATA, in the standard's term.
func isEscapableRawText(_ tag: string) -> bool {
    return tag == "textarea" || tag == "title"
}
