# SwiftSyntax

SwiftSyntax is a set of Swift bindings for the
[libSyntax](https://github.com/apple/swift/tree/master/lib/Syntax) library. It
allows for Swift tools to parse, inspect, generate, and transform Swift source
code.

> Note: SwiftSyntax is still in development, and the API is not guaranteed to
> be stable. It's subject to change without warning.

## Usage

Add this repository to the `Package.swift` manifest of your project:

```swift
import PackageDescription

let package = Package(
  name: "MyTool",
  dependencies: [
    .package(url: "https://github.com/apple/swift-syntax.git", .branch("<#Specify Release tag#>")),
  ],
  targets: [
    .target(name: "MyTool", dependencies: ["SwiftSyntax"]),
  ]
)
```

Replace `<#Specify Release tag#>` by the version of SwiftSyntax that you want to use. Tags will be created for every release of the compiler in the form `swift-4.2-RELEASE` and for every nightly build in the form `swift-4.2-DEVELOPMENT-SNAPSHOT-2018-08-25-a`.

Then, import `SwiftSyntax` in your Swift code.

## Contributing

### Building SwiftSyntax from `master`
Since SwiftSyntax relies on definitions in the main Swift repository to generate the layout of the syntax tree using `gyb`, a checkout of [apple/swift](https://github.com/apple/swift) is still required to build `master` of SwiftSyntax.

To build the `master` version of SwiftSyntax, check `swift-syntax` and  `swift` out side by side
```
- (enclosing directory)
  - swift
  - swift-syntax
```

And run `swift-syntax/build-script.py`. SwiftSyntax is now being built with the Swift compiler installed on the system.

Swift-CI will automatically run the code generation step whenever a new toolchain (development snapshot or release) is published. It should thus almost never be necessary to perform the above build yourself. 

Afterwards, SwiftPM can also generate an Xcode project to develop SwiftSyntax by running `swift package generate-xcodeproj`.

If you also want to run tests locally, read the section below as testing has additional requirements. 

### Local Testing
SwiftSyntax uses some test utilities that need to be built as part of the Swift compiler project. To build the most recent version of SwiftSyntax and test it, follow the steps in [swift/README.md](https://github.com/apple/swift/blob/master/README.md) and pass `--llbuild --swiftpm --swiftsyntax` to the build script invocation to build SwiftSyntax and all its dependencies using the current `master` compiler. 

SwiftSyntax can then be tested using the build script in `apple/swift` by running 
```
swift/utils/build-script --swiftsyntax --swiftpm --llbuild -t --skip-test-cmark --skip-test-swift --skip-test-llbuild --skip-test-swiftpm
```
This command will build SwiftSyntax and all its dependencies, tell the build script to run tests, but skip all tests but the SwiftSyntax tests. 

Note that it is not currently supported to SwiftSyntax while building the Swift compiler using Xcode.

### CI Testing

Running `@swift-ci Please test` on the main Swift repository will also test the most recent version of SwiftSyntax. 

Testing SwiftSyntax from its own repository will be available in the near future.

## Example

This is a program that adds 1 to every integer literal in a Swift file.

```swift
import SwiftSyntax
import Foundation

/// AddOneToIntegerLiterals will visit each token in the Syntax tree, and
/// (if it is an integer literal token) add 1 to the integer and return the
/// new integer literal token.
class AddOneToIntegerLiterals: SyntaxRewriter {
  override func visit(_ token: TokenSyntax) -> Syntax {
    // Only transform integer literals.
    guard case .integerLiteral(let text) = token.tokenKind else {
      return token
    }

    // Remove underscores from the original text.
    let integerText = String(text.filter { ("0"..."9").contains($0) })

    // Parse out the integer.
    let int = Int(integerText)!

    // Return a new integer literal token with `int + 1` as its text.
    return token.withKind(.integerLiteral("\(int + 1)"))
  }
}

let file = CommandLine.arguments[1]
let url = URL(fileURLWithPath: file)
let sourceFile = try SyntaxTreeParser.parse(url)
let incremented = AddOneToIntegerLiterals().visit(sourceFile)
print(incremented)
```

This example turns this:

```swift
let x = 2
let y = 3_000
```

into:

```swift
let x = 3
let y = 3001
```
