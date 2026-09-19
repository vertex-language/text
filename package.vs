// The 'text' package: HTML and CSS format parsers and tools for Vertex.
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
        .executable(name: "check", targets: ["check"]),
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
        .executableTarget(
            name: "check",
            dependencies: ["html", "css", "selector"],
            path: "tests/check"
        ),
    ]
)
