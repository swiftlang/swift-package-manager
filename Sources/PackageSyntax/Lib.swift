import SwiftSyntax

public func DoSomethingWithSwiftSyntax() throws -> String {
    let parsed = try SyntaxParser.parse(source: "let abc = 42")
    print(parsed)
    return parsed.description
}
