// The 'text' package: HTML and CSS format parsers, tokenizers, and tools for Vertex.
import PackageDescription

let package = Package(
    name: "text",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "text/html", targets: ["html"]),
        .library(name: "text/css", targets: ["css"]),
        .library(name: "text/css/selector", targets: ["selector"]),
        .library(name: "text/tokenizer", targets: ["tokenizer"]),
        .executable(name: "check", targets: ["check"]),
        .executable(name: "test-tokenizer", targets: ["test_tokenizer"]),
    ],
    targets: [
        .target(
            name: "html",
            path: "html"
        ),
        .target(
            name: "css",
            path: "css"
        ),
        .target(
            name: "selector",
            dependencies: ["html", "css"],
            path: "selector"
        ),
        // Text to a model's token ids and back, driven by the vocabulary.
        .target(
            name: "tokenizer",
            path: "tokenizer"
        ),
        .executableTarget(
            name: "test_tokenizer",
            dependencies: ["tokenizer"],
            path: "tests/tokenizer",
            exclude: ["testdata", "golden", "oracle"]
        ),
        .executableTarget(
            name: "check",
            dependencies: ["html", "css", "selector"],
            path: "tests/check"
        ),
    ]
)
