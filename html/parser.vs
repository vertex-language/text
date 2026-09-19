package html

/// Parses HTML tokens into an HTML Document tree.
public class Parser {
    var scanner: Scanner
    var root: Node
    var stack: [Node]

    public init(scanner: Scanner) {
        self.scanner = scanner
        self.root = Node(kind: NodeKind.document)
        self.stack = [self.root]
    }

    /// Parses the entire HTML stream and returns the Document.
    public func Parse() -> Document {
        while true {
            let token = scanner.Next()
            if token.Kind == TokenKind.eof {
                break
            }

            switch token.Kind {
            case .text:
                if !token.Data.isEmpty {
                    let textNode = Node(kind: NodeKind.text, text: token.Data)
                    stack[stack.count - 1].AppendChild(textNode)
                }

            case .comment:
                let commentNode = Node(kind: NodeKind.comment, text: token.Data)
                stack[stack.count - 1].AppendChild(commentNode)

            case .doctype:
                break

            case .selfClosingTag:
                let elem = Node(kind: NodeKind.element, tagName: token.Data, attributes: token.Attributes)
                stack[stack.count - 1].AppendChild(elem)

            case .startTag:
                let elem = Node(kind: NodeKind.element, tagName: token.Data, attributes: token.Attributes)
                stack[stack.count - 1].AppendChild(elem)

                // If this is <script> or <style>, scan raw body text directly
                if isRawTextElement(token.Data) {
                    let rawTextToken = scanner.ScanRawTextUntilClose(tag: token.Data)
                    if !rawTextToken.Data.isEmpty {
                        let textNode = Node(kind: NodeKind.text, text: rawTextToken.Data)
                        elem.AppendChild(textNode)
                    }
                    // Scanner is now positioned at </script> or </style>, let loop consume it
                } else {
                    stack.append(elem)
                }

            case .endTag:
                // Find matching tag in the stack from top down
                var i = stack.count - 1
                while i > 0 {
                    if toLower(stack[i].TagName) == toLower(token.Data) {
                        // Pop stack down to this element
                        while stack.count > i {
                            _ = stack.remove(at: stack.count - 1)
                        }
                        break
                    }
                    i -= 1
                }

            case .eof:
                break
            }
        }

        return Document(root: root)
    }
}
