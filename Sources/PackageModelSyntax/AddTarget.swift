//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Add a target to a manifest's source code.
public struct AddTarget {
    /// The set of argument labels that can occur after the "targets"
    /// argument in the Package initializers.
    ///
    /// TODO: Could we generate this from the the PackageDescription module, so
    /// we don't have keep it up-to-date manually?
    private static let argumentLabelsAfterTargets: Set<String> = [
        "swiftLanguageVersions",
        "cLanguageStandard",
        "cxxLanguageStandard"
    ]

    /// Add the given target to the manifest, producing a set of edit results
    /// that updates the manifest and adds some source files to stub out the
    /// new target.
    public static func addTarget(
        _ target: TargetDescription,
        to manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        // Make sure we have a suitable tools version in the manifest.
        try manifest.checkEditManifestToolsVersion()

        guard let packageCall = manifest.findCall(calleeName: "Package") else {
            throw ManifestEditError.cannotFindPackage
        }

        let manifestEdits = try packageCall.appendingToArrayArgument(
            label: "targets",
            trailingLabels: Self.argumentLabelsAfterTargets,
            newElement: target.asSyntax()
        )

        let outerDirectory: String? = switch target.type {
        case .binary, .macro, .plugin, .system: nil
        case .executable, .regular: "Sources"
        case .test: "Tests"
        }

        guard let outerDirectory else {
            return PackageEditResult(manifestEdits: manifestEdits)
        }

        let sourceFilePath = try RelativePath(validating: outerDirectory)
            .appending(components: [target.name, "\(target.name).swift"])

        // Introduce imports for each of the dependencies that were specified.
        var importModuleNames = target.dependencies.map {
            $0.name
        }

        // Add appropriate test module dependencies.
        if target.type == .test {
            importModuleNames.append("XCTest")
        }

        let importDecls = importModuleNames.lazy.sorted().map { name in
            DeclSyntax("import \(raw: name)").with(\.trailingTrivia, .newline)
        }

        let imports = CodeBlockItemListSyntax {
            for importDecl in importDecls {
                importDecl
            }
        }

        let sourceFileText: SourceFileSyntax = switch target.type {
        case .binary, .macro, .plugin, .system:
            fatalError("should have exited above")

        case .test:
            """
            \(imports)
            class \(raw: target.name): XCTestCase {
                func test\(raw: target.name)() {
                    XCTAssertEqual(42, 17 + 25)
                }
            }
            """

        case .regular:
            """
            \(imports)
            """

        case .executable:
            """
            \(imports)
            @main
            struct \(raw: target.name)Main {
                static func main() {
                    print("Hello, world")
                }
            }
            """
        }

        return PackageEditResult(
            manifestEdits: manifestEdits,
            auxiliaryFiles: [(sourceFilePath, sourceFileText)]
        )
    }
}

fileprivate extension TargetDescription.Dependency {
    /// Retrieve the name of the dependency
    var name: String {
        switch self {
        case .target(name: let name, condition: _),
            .byName(name: let name, condition: _),
            .product(name: let name, package: _, moduleAliases: _, condition: _):
            name
        }
    }
}
