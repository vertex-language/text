# text

[![package: stdlib](https://img.shields.io/badge/package-stdlib-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![text: html | css | selector](https://img.shields.io/badge/text-html%20%7C%20css%20%7C%20selector-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/text)
[![runtime: pure-vertex](https://img.shields.io/badge/runtime-pure--vertex-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)

Standard text format parsers for the Vertex programming language, providing 100% pure Vertex parsers and tree models for HTML and CSS.

---

## Packages

- **`text/html`**: HTML tokenizer, DOM tree (`Document`, `Node`), entity escaping/unescaping, and serializer.
- **`text/css`**: CSS tokenizer, declaration blocks, at-rules (`@media`), and stylesheet parser.
- **`text/css/selector`**: CSS selectors parser and matcher with complex combinators (`>`, space, `+`, `~`), attribute operators, pseudo-classes, and specificity calculation.

---

## Quick Start

### Parsing and Querying HTML

```swift
package main

import "text/html"
import "text/css/selector"

func main() -> int32 {
    let source = """
    <div id="app" class="container">
      <h1>Hello Vertex</h1>
      <ul class="items">
        <li class="item active"><a href="https://vertex.dev">Home</a></li>
        <li class="item"><a href="/docs">Docs</a></li>
      </ul>
    </div>
    """

    let doc = html.Parse(source)

    // DOM lookups
    if let app = doc.ElementById("app") {
        print("Found container with tag: \(app.TagName), classes: \(app.Classes())")
    }

    // CSS Selector queries
    let activeLinks = selector.QuerySelectorAll("ul.items > li.active a", in: doc.Root)
    for link in activeLinks {
        print("Active link: \(link.GetAttribute("href") ?? "") - \(link.InnerText())")
    }

    // Render back to string
    print(html.Render(doc.Root))
    return 0
}
```

### Parsing CSS

```swift
package main

import "text/css"

func main() -> int32 {
    let style = """
    body {
        margin: 0;
        color: #24292f;
        font-family: system-ui, sans-serif;
    }
    .btn.primary {
        background-color: #0969da !important;
        padding: 8px 16px;
    }
    """

    let sheet = css.Parse(style)
    for rule in sheet.Rules {
        print("Rule selectors: \(rule.Selectors)")
        if let bg = rule.GetDeclaration("background-color") {
            print("  background-color: \(bg.Value) (important: \(bg.Important))")
        }
    }

    // Parse inline style
    let inline = css.ParseDeclarations("color: red; font-size: 14px;")
    print("Parsed \(inline.count) inline declarations")
    return 0
}
```

---

## Running Tests

Execute the comprehensive test suite directly with `vsc`:

```bash
vsc run check
```

---

## License

[MIT](LICENSE)
