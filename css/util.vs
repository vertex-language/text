package css

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
    return b == 32 || b == 9 || b == 10 || b == 13 || b == 12
}

func isIdentStart(_ b: uint8) -> bool {
    return (b >= 97 && b <= 122) || // 'a'...'z'
           (b >= 65 && b <= 90) ||  // 'A'...'Z'
           b == 95 || b == 45       // '_', '-'
}

func isIdentChar(_ b: uint8) -> bool {
    return isIdentStart(b) || (b >= 48 && b <= 57) // '0'...'9'
}

func isDigit(_ b: uint8) -> bool {
    return b >= 48 && b <= 57
}

func trimString(_ s: string) -> string {
    let bytes = bytesFromString(s)
    if bytes.isEmpty { return "" }
    var start = 0
    while start < bytes.count && isWhitespace(bytes[start]) {
        start += 1
    }
    var end = bytes.count
    while end > start && isWhitespace(bytes[end - 1]) {
        end -= 1
    }
    return stringFromBytes(bytes, from: start, to: end)
}
