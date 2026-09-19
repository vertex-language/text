package selector

import "text/html"
import "text/css"

/// What a page's state says about its elements, which the dynamic
/// pseudo-classes ask: which element the pointer is over, which has the
/// keyboard, which is being pressed. An element is hovered when it or a
/// descendant is under the pointer, as `:hover` applies to ancestors.
public final class MatchContext {
    public var Hovered: html.Node?
    public var Focused: html.Node?
    public var Active: html.Node?

    public init() {
        Hovered = nil
        Focused = nil
        Active = nil
    }

    /// An empty context: nothing hovered, focused or active.
    public static let none = MatchContext()

    func isHovered(_ node: html.Node) -> bool {
        var cur = Hovered
        while let n = cur {
            if n.Id == node.Id { return true }
            cur = n.Parent
        }
        return false
    }

    func isActive(_ node: html.Node) -> bool {
        var cur = Active
        while let n = cur {
            if n.Id == node.Id { return true }
            cur = n.Parent
        }
        return false
    }
}

/// Matches a single compound part against an HTML element node.
public func MatchPart(_ part: SelectorPart, _ node: html.Node) -> bool {
    return MatchPartIn(part, node, MatchContext.none)
}

public func MatchPartIn(_ part: SelectorPart, _ node: html.Node, _ ctx: MatchContext) -> bool {
    if node.Kind != html.NodeKind.element {
        return false
    }

    // A pseudo-element is not an element.
    if part.PseudoElement != nil {
        return false
    }

    // Tag name check; tag names are lowercase on both sides.
    if let tag = part.Tag {
        if tag != "*" && node.TagName != tag {
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

    // Pseudo-classes
    var k = 0
    while k < part.Pseudos.count {
        if !matchPseudo(part.Pseudos[k], node, ctx) { return false }
        k += 1
    }

    return true
}

func matchPseudo(_ p: Pseudo, _ node: html.Node, _ ctx: MatchContext) -> bool {
    switch p.Name {
    case "first-child":
        return node.PreviousElementSibling() == nil
    case "last-child":
        return node.NextElementSibling() == nil
    case "only-child":
        return node.PreviousElementSibling() == nil && node.NextElementSibling() == nil
    case "first-of-type":
        return previousOfType(node) == nil
    case "last-of-type":
        return nextOfType(node) == nil
    case "only-of-type":
        return previousOfType(node) == nil && nextOfType(node) == nil
    case "nth-child":
        return nthMatches(p.A, p.B, indexAmongSiblings(node, ofType: false, fromEnd: false))
    case "nth-last-child":
        return nthMatches(p.A, p.B, indexAmongSiblings(node, ofType: false, fromEnd: true))
    case "nth-of-type":
        return nthMatches(p.A, p.B, indexAmongSiblings(node, ofType: true, fromEnd: false))
    case "nth-last-of-type":
        return nthMatches(p.A, p.B, indexAmongSiblings(node, ofType: true, fromEnd: true))
    case "root":
        return node.Parent == nil || node.Parent?.Kind == html.NodeKind.document
    case "empty":
        var i = 0
        while i < node.Children.count {
            let c = node.Children[i]
            if c.Kind == html.NodeKind.element { return false }
            if c.Kind == html.NodeKind.text && !c.Text.isEmpty { return false }
            i += 1
        }
        return true
    case "hover":
        return ctx.isHovered(node)
    case "active":
        return ctx.isActive(node)
    case "focus", "focus-visible":
        if let f = ctx.Focused { return f.Id == node.Id }
        return false
    case "focus-within":
        var cur = ctx.Focused
        while let n = cur {
            if n.Id == node.Id { return true }
            cur = n.Parent
        }
        return false
    case "link", "any-link":
        return (node.TagName == "a" || node.TagName == "area") && node.HasAttribute("href")
    case "visited":
        return false
    case "checked":
        if node.TagName == "option" { return node.HasAttribute("selected") }
        return node.HasAttribute("checked")
    case "disabled":
        return node.HasAttribute("disabled")
    case "enabled":
        return isFormControl(node) && !node.HasAttribute("disabled")
    case "required":
        return node.HasAttribute("required")
    case "optional":
        return isFormControl(node) && !node.HasAttribute("required")
    case "placeholder-shown":
        return node.HasAttribute("placeholder") && (node.GetAttribute("value") ?? "").isEmpty
    case "not":
        var i = 0
        while i < p.Inner.count {
            if MatchComplexIn(p.Inner[i], node, ctx) { return false }
            i += 1
        }
        return true
    case "is", "where", "matches":
        var i = 0
        while i < p.Inner.count {
            if MatchComplexIn(p.Inner[i], node, ctx) { return true }
            i += 1
        }
        return false
    case "has":
        var i = 0
        while i < p.Inner.count {
            if hasDescendantMatching(node, p.Inner[i], ctx) { return true }
            i += 1
        }
        return false
    case "lang", "dir", "target", "defined":
        return p.Name == "defined"
    default:
        return false
    }
}

func isFormControl(_ node: html.Node) -> bool {
    let t = node.TagName
    return t == "input" || t == "button" || t == "select" || t == "textarea" || t == "option" || t == "fieldset"
}

func hasDescendantMatching(_ node: html.Node, _ sel: ComplexSelector, _ ctx: MatchContext) -> bool {
    var i = 0
    while i < node.Children.count {
        let c = node.Children[i]
        if c.Kind == html.NodeKind.element {
            if MatchComplexIn(sel, c, ctx) { return true }
            if hasDescendantMatching(c, sel, ctx) { return true }
        }
        i += 1
    }
    return false
}

func previousOfType(_ node: html.Node) -> html.Node? {
    var cur = node.PreviousElementSibling()
    while let n = cur {
        if n.TagName == node.TagName { return n }
        cur = n.PreviousElementSibling()
    }
    return nil
}

func nextOfType(_ node: html.Node) -> html.Node? {
    var cur = node.NextElementSibling()
    while let n = cur {
        if n.TagName == node.TagName { return n }
        cur = n.NextElementSibling()
    }
    return nil
}

/// The 1-based position of an element among its parent's element
/// children, counting only those of its type when asked, from the end
/// when asked.
func indexAmongSiblings(_ node: html.Node, ofType: bool, fromEnd: bool) -> int {
    guard let p = node.Parent else { return 1 }
    var index = 0
    var i = fromEnd ? p.Children.count - 1 : 0
    while i >= 0 && i < p.Children.count {
        let c = p.Children[i]
        if c.Kind == html.NodeKind.element && (!ofType || c.TagName == node.TagName) {
            index += 1
            if c.Id == node.Id { return index }
        }
        i += fromEnd ? -1 : 1
    }
    return index
}

/// Whether index is An+B for some n >= 0.
func nthMatches(_ a: int, _ b: int, _ index: int) -> bool {
    if a == 0 { return index == b }
    let diff = index - b
    if diff % a != 0 { return false }
    return diff / a >= 0
}

/// Matches a complex selector (e.g. `div.menu > ul li a`) against an element node.
public func MatchComplex(_ complex: ComplexSelector, _ node: html.Node) -> bool {
    return MatchComplexIn(complex, node, MatchContext.none)
}

/// Matches a complex selector against an element, with the page's state
/// for the dynamic pseudo-classes.
public func MatchComplexIn(_ complex: ComplexSelector, _ node: html.Node, _ ctx: MatchContext) -> bool {
    if node.Kind != html.NodeKind.element {
        return false
    }

    let compounds = complex.Compounds
    if compounds.isEmpty { return false }

    let lastIdx = compounds.count - 1
    // The target element must match the rightmost compound selector
    if !MatchPartIn(compounds[lastIdx].Part, node, ctx) {
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
            if !MatchPartIn(compounds[curCompoundIdx].Part, cur, ctx) {
                return false
            }

        case .descendant, .none:
            currentNode = currentNode?.Parent
            var matched = false
            while let cur = currentNode {
                if MatchPartIn(compounds[curCompoundIdx].Part, cur, ctx) {
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
            if !MatchPartIn(compounds[curCompoundIdx].Part, cur, ctx) {
                return false
            }

        case .generalSibling:
            currentNode = currentNode?.PreviousElementSibling()
            var matched = false
            while let cur = currentNode {
                if MatchPartIn(compounds[curCompoundIdx].Part, cur, ctx) {
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
