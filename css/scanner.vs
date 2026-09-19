package css

/// Tokenizer that scans CSS source bytes into a CSS Token stream.
public class Scanner {
    var src: [uint8]
    var pos: int
    var len: int

    public init(bytes: [uint8]) {
        self.src = bytes
        self.pos = 0
        self.len = bytes.count
    }

    public init(source: string) {
        self.src = bytesFromString(source)
        self.pos = 0
        self.len = self.src.count
    }

    /// Fetches the next token from the CSS stream.
    public func Next() -> Token {
        skipWhitespaceAndComments()
        if pos >= len {
            return Token(kind: TokenKind.eof)
        }

        let b = src[pos]

        // Punctuation and brackets
        if b == 123 { pos += 1; return Token(kind: TokenKind.openBrace, value: "{") }  // '{'
        if b == 125 { pos += 1; return Token(kind: TokenKind.closeBrace, value: "}") } // '}'
        if b == 58  { pos += 1; return Token(kind: TokenKind.colon, value: ":") }      // ':'
        if b == 59  { pos += 1; return Token(kind: TokenKind.semicolon, value: ";") }  // ';'
        if b == 44  { pos += 1; return Token(kind: TokenKind.comma, value: ",") }      // ','
        if b == 40  { pos += 1; return Token(kind: TokenKind.openParen, value: "(") }  // '('
        if b == 41  { pos += 1; return Token(kind: TokenKind.closeParen, value: ")") } // ')'
        if b == 91  { pos += 1; return Token(kind: TokenKind.openBracket, value: "[") } // '['
        if b == 93  { pos += 1; return Token(kind: TokenKind.closeBracket, value: "]") } // ']'

        // Strings
        if b == 34 || b == 39 { // '"' or '\''
            return scanString(quote: b)
        }

        // At-keyword: @media, @import
        if b == 64 { // '@'
            pos += 1
            let start = pos
            while pos < len && isIdentChar(src[pos]) {
                pos += 1
            }
            let kw = stringFromBytes(src, from: start, to: pos)
            return Token(kind: TokenKind.atKeyword, value: kw)
        }

        // Hash / ID: #header, #fff
        if b == 35 { // '#'
            pos += 1
            let start = pos
            while pos < len && (isIdentChar(src[pos]) || src[pos] == 45) {
                pos += 1
            }
            let hashVal = "#" + stringFromBytes(src, from: start, to: pos)
            return Token(kind: TokenKind.hash, value: hashVal)
        }

        // Numbers, Dimensions, Percentages
        if isDigit(b) || (b == 46 && pos + 1 < len && isDigit(src[pos + 1])) { // digit or '.'
            return scanNumberOrDimension()
        }

        // Identifiers
        if isIdentStart(b) {
            return scanIdent()
        }

        // Single delimiter character (. > + ~ * ! /)
        pos += 1
        var singleChar: [CChar] = [CChar(truncatingIfNeeded: b), 0]
        return Token(kind: TokenKind.delim, value: string(cString: singleChar))
    }

    func scanString(quote: uint8) -> Token {
        pos += 1 // skip quote
        let start = pos
        while pos < len && src[pos] != quote {
            if src[pos] == 92 && pos + 1 < len { // '\' escape
                pos += 2
                continue
            }
            pos += 1
        }
        let text = stringFromBytes(src, from: start, to: pos)
        if pos < len && src[pos] == quote {
            pos += 1
        }
        return Token(kind: TokenKind.string, value: text)
    }

    func scanIdent() -> Token {
        let start = pos
        while pos < len && isIdentChar(src[pos]) {
            pos += 1
        }
        let val = stringFromBytes(src, from: start, to: pos)
        return Token(kind: TokenKind.ident, value: val)
    }

    func scanNumberOrDimension() -> Token {
        let start = pos
        var isFloat = false

        while pos < len && isDigit(src[pos]) {
            pos += 1
        }
        if pos < len && src[pos] == 46 && pos + 1 < len && isDigit(src[pos + 1]) { // '.'
            isFloat = true
            pos += 1
            while pos < len && isDigit(src[pos]) {
                pos += 1
            }
        }

        let numStr = stringFromBytes(src, from: start, to: pos)
        var numVal: float32 = 0.0
        // Parse float32 from string
        numVal = parseNumber(numStr)

        if pos < len && src[pos] == 37 { // '%'
            pos += 1
            return Token(kind: TokenKind.percentage, value: numStr + "%", unit: "%", numberVal: numVal)
        }

        if pos < len && isIdentStart(src[pos]) {
            let unitStart = pos
            while pos < len && isIdentChar(src[pos]) {
                pos += 1
            }
            let unitStr = stringFromBytes(src, from: unitStart, to: pos)
            return Token(kind: TokenKind.dimension, value: numStr + unitStr, unit: unitStr, numberVal: numVal)
        }

        return Token(kind: TokenKind.number, value: numStr, unit: "", numberVal: numVal)
    }

    func parseNumber(_ s: string) -> float32 {
        let bytes = bytesFromString(s)
        var integerPart: float32 = 0.0
        var fracPart: float32 = 0.0
        var fracDiv: float32 = 10.0
        var seenDot = false

        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 46 { // '.'
                seenDot = true
            } else if b >= 48 && b <= 57 {
                let digit = float32(b - 48)
                if seenDot {
                    fracPart += digit / fracDiv
                    fracDiv *= 10.0
                } else {
                    integerPart = integerPart * 10.0 + digit
                }
            }
            i += 1
        }
        return integerPart + fracPart
    }

    func skipWhitespaceAndComments() {
        while pos < len {
            if isWhitespace(src[pos]) {
                pos += 1
                continue
            }
            // Comment: /* ... */
            if src[pos] == 47 && pos + 1 < len && src[pos + 1] == 42 { // "/*"
                pos += 2
                while pos + 1 < len {
                    if src[pos] == 42 && src[pos + 1] == 47 { // "*/"
                        pos += 2
                        break
                    }
                    pos += 1
                }
                continue
            }
            break
        }
    }
}
