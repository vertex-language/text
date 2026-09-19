package css

/// Parser that converts CSS tokens into a StyleSheet or Declaration list.
public class Parser {
    var scanner: Scanner
    var current: Token

    public init(scanner: Scanner) {
        self.scanner = scanner
        self.current = scanner.Next()
    }

    func advance() {
        self.current = scanner.Next()
    }

    /// Parses the entire CSS stream into a StyleSheet.
    public func Parse() -> StyleSheet {
        var rules: [Rule] = []
        var atRules: [AtRule] = []

        while current.Kind != TokenKind.eof {
            if current.Kind == TokenKind.atKeyword {
                let name = current.Value
                advance()
                // Collect params until '{' or ';'
                var params = ""
                while current.Kind != TokenKind.openBrace && current.Kind != TokenKind.semicolon && current.Kind != TokenKind.eof {
                    let curVal = current.Value
                    if !params.isEmpty {
                        let lastB = bytesFromString(params).last ?? 0
                        let firstB = bytesFromString(curVal).first ?? 0
                        if lastB != 40 && firstB != 41 && firstB != 58 {
                            params += " "
                        }
                    }
                    params += curVal
                    advance()
                }
                if current.Kind == TokenKind.openBrace {
                    advance() // skip '{'
                    var innerRules: [Rule] = []
                    while current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
                        if let rule = parseRule() {
                            innerRules.append(rule)
                        }
                    }
                    if current.Kind == TokenKind.closeBrace {
                        advance()
                    }
                    atRules.append(AtRule(name: name, params: trimString(params), rules: innerRules))
                } else if current.Kind == TokenKind.semicolon {
                    advance()
                    atRules.append(AtRule(name: name, params: trimString(params), rules: []))
                }
            } else {
                if let rule = parseRule() {
                    rules.append(rule)
                }
            }
        }

        return StyleSheet(rules: rules, atRules: atRules)
    }

    /// Parses a single CSS rule (selectors + declaration block).
    func parseRule() -> Rule? {
        var selectors: [string] = []
        var currentSel = ""

        // Collect selectors until '{'
        while current.Kind != TokenKind.openBrace && current.Kind != TokenKind.eof {
            if current.Kind == TokenKind.comma {
                let s = trimString(currentSel)
                if !s.isEmpty {
                    selectors.append(s)
                }
                currentSel = ""
                advance()
                continue
            }
            if !currentSel.isEmpty {
                // If previous char wasn't a delimiter like '.', '#', '>', add space
                let lastB = bytesFromString(currentSel).last ?? 0
                let curB = bytesFromString(current.Value).first ?? 0
                if curB != 46 && curB != 35 && curB != 58 && curB != 62 && lastB != 46 && lastB != 35 && lastB != 58 && lastB != 62 {
                    currentSel += " "
                }
            }
            currentSel += current.Value
            advance()
        }

        let lastSel = trimString(currentSel)
        if !lastSel.isEmpty {
            selectors.append(lastSel)
        }

        if current.Kind != TokenKind.openBrace {
            return nil
        }
        advance() // skip '{'

        let decls = parseDeclarationBlock()
        return Rule(selectors: selectors, declarations: decls)
    }

    /// Parses declarations until matching '}'.
    func parseDeclarationBlock() -> [Declaration] {
        var decls: [Declaration] = []

        while current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
            // Expect property name
            if current.Kind == TokenKind.ident {
                let prop = current.Value
                advance()

                if current.Kind == TokenKind.colon {
                    advance() // skip ':'

                    var val = ""
                    var important = false

                    while current.Kind != TokenKind.semicolon && current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
                        if current.Kind == TokenKind.delim && current.Value == "!" {
                            advance()
                            if current.Kind == TokenKind.ident && toLower(current.Value) == "important" {
                                important = true
                                advance()
                                continue
                            }
                        }
                        if !val.isEmpty {
                            val += " "
                        }
                        val += current.Value
                        advance()
                    }

                    decls.append(Declaration(property: prop, value: trimString(val), important: important))

                    if current.Kind == TokenKind.semicolon {
                        advance()
                    }
                } else {
                    // Syntax error: skip to next semicolon or brace
                    skipToNextDeclaration()
                }
            } else {
                advance()
            }
        }

        if current.Kind == TokenKind.closeBrace {
            advance()
        }

        return decls
    }

    func skipToNextDeclaration() {
        while current.Kind != TokenKind.semicolon && current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
            advance()
        }
        if current.Kind == TokenKind.semicolon {
            advance()
        }
    }
}
