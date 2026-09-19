package selector

import "text/html"
import "text/css"

/// Matches a single compound part against an HTML element node.
public func MatchPart(_ part: SelectorPart, _ node: html.Node) -> bool {
    if node.Kind != html.NodeKind.element {
        return false
    }

    // Tag name check
    if let tag = part.Tag {
        if tag != "*" && toLower(node.TagName) != toLower(tag) {
            return false
        }
    }

    // ID check (#id)
    if let id = part.Id {
        if node.IdAttr() != id {
            return false
        }
    }

    // Classes check (.class)
    var i = 0
    while i < part.Classes.count {
        if !node.HasClass(part.Classes[i]) {
            return false
        }
        i += 1
    }

    // Attribute selectors ([attr], [attr=val], [attr^=val], etc.)
    var j = 0
    while j < part.Attributes.count {
        let attrSel = part.Attributes[j]
        guard let val = node.GetAttribute(attrSel.Name) else {
            return false
        }
        switch attrSel.Op {
        case .exists:
            break
        case .exact:
            if val != attrSel.Value { return false }
        case .prefix:
            if !hasPrefix(val, attrSel.Value) { return false }
        case .suffix:
            if !hasSuffix(val, attrSel.Value) { return false }
        case .contains:
            if !contains(val, attrSel.Value) { return false }
        }
        j += 1
    }

    // Pseudo-classes (:first-child, :last-child)
    var k = 0
    while k < part.PseudoClasses.count {
        let pseudo = toLower(part.PseudoClasses[k])
        if pseudo == "first-child" {
            if node.PreviousElementSibling() != nil { return false }
        } else if pseudo == "last-child" {
            if node.NextElementSibling() != nil { return false }
        }
        k += 1
    }

    return true
}

/// Matches a complex selector (e.g. `div.menu > ul li a`) against an element node.
public func MatchComplex(_ complex: ComplexSelector, _ node: html.Node) -> bool {
    if node.Kind != html.NodeKind.element {
        return false
    }

    let compounds = complex.Compounds
    if compounds.isEmpty { return false }

    let lastIdx = compounds.count - 1
    // The target element must match the rightmost compound selector
    if !MatchPart(compounds[lastIdx].Part, node) {
        return false
    }

    var curCompoundIdx = lastIdx - 1
    var currentNode: html.Node? = node

    while curCompoundIdx >= 0 {
        let comb = compounds[curCompoundIdx].CombinatorWithNext

        switch comb {
        case .child:
            currentNode = currentNode?.Parent
            guard let cur = currentNode else { return false }
            if !MatchPart(compounds[curCompoundIdx].Part, cur) {
                return false
            }

        case .descendant, .none:
            currentNode = currentNode?.Parent
            var matched = false
            while let cur = currentNode {
                if MatchPart(compounds[curCompoundIdx].Part, cur) {
                    matched = true
                    currentNode = cur
                    break
                }
                currentNode = cur.Parent
            }
            if !matched { return false }

        case .adjacentSibling:
            currentNode = currentNode?.PreviousElementSibling()
            guard let cur = currentNode else { return false }
            if !MatchPart(compounds[curCompoundIdx].Part, cur) {
                return false
            }

        case .generalSibling:
            currentNode = currentNode?.PreviousElementSibling()
            var matched = false
            while let cur = currentNode {
                if MatchPart(compounds[curCompoundIdx].Part, cur) {
                    matched = true
                    currentNode = cur
                    break
                }
                currentNode = cur.PreviousElementSibling()
            }
            if !matched { return false }
        }

        curCompoundIdx -= 1
    }

    return true
}

// String helpers for attribute matching
func toLower(_ s: string) -> string {
    var b: [uint8] = []
    for byte in s.utf8 {
        if byte >= 65 && byte <= 90 {
            b.append(byte + 32)
        } else {
            b.append(byte)
        }
    }
    return strFrom(b, 0, b.count)
}

func hasPrefix(_ str: string, _ prefix: string) -> bool {
    let sb = bytesFrom(str)
    let pb = bytesFrom(prefix)
    if pb.count > sb.count { return false }
    var i = 0
    while i < pb.count {
        if sb[i] != pb[i] { return false }
        i += 1
    }
    return true
}

func hasSuffix(_ str: string, _ suffix: string) -> bool {
    let sb = bytesFrom(str)
    let pb = bytesFrom(suffix)
    if pb.count > sb.count { return false }
    let offset = sb.count - pb.count
    var i = 0
    while i < pb.count {
        if sb[offset + i] != pb[i] { return false }
        i += 1
    }
    return true
}

func contains(_ str: string, _ needle: string) -> bool {
    let sb = bytesFrom(str)
    let nb = bytesFrom(needle)
    if nb.isEmpty { return true }
    if nb.count > sb.count { return false }
    var i = 0
    while i <= sb.count - nb.count {
        var match = true
        var j = 0
        while j < nb.count {
            if sb[i + j] != nb[j] {
                match = false
                break
            }
            j += 1
        }
        if match { return true }
        i += 1
    }
    return false
}
