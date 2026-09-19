package css

/// A single CSS property declaration, such as `color: red !important;`.
public struct Declaration: Equatable {
    public var Property: string
    public var Value: string
    public var Important: bool

    public init(property: string, value: string, important: bool = false) {
        self.Property = toLower(property)
        self.Value = value
        self.Important = important
    }
}
