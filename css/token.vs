package css

/// The kind of CSS token produced by the scanner.
public enum TokenKind: Equatable {
    case eof
    case ident
    case hash
    case string
    case number
    case dimension
    case percentage
    case colon
    case semicolon
    case comma
    case openBrace
    case closeBrace
    case openParen
    case closeParen
    case openBracket
    case closeBracket
    case atKeyword
    case delim
}

/// A CSS token emitted by the scanner.
public struct Token {
    public var Kind: TokenKind
    public var Value: string
    public var Unit: string
    public var NumberVal: float32

    public init(kind: TokenKind, value: string = "", unit: string = "", numberVal: float32 = 0.0) {
        self.Kind = kind
        self.Value = value
        self.Unit = unit
        self.NumberVal = numberVal
    }
}
