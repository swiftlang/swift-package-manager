//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SwiftSyntax
import SwiftSyntaxBuilder

/// Errors raised by `InitWorkspace.write()` when scaffolding a new
/// workspace under `swift workspace init`.
public enum InitWorkspaceError: Error, Equatable {
    /// The destination already contains a `Workspace.swift`.
    /// `init workspace` never overwrites; users must remove the
    /// existing file themselves if they want to regenerate.
    /// - Parameter path: The absolute path of the existing file.
    case workspaceManifestAlreadyExists(AbsolutePath)

    /// A member path is absolute. Member paths must be relative to
    /// the workspace root — declared members live inside the
    /// workspace tree.
    /// - Parameter path: The offending absolute-looking path as
    ///   supplied on the CLI.
    case absoluteMemberPath(String)
}

/// Scaffolds a new SwiftPM workspace: creates a `Workspace.swift`
/// manifest at the destination and, for each declared member,
/// creates a directory with a `Package.swift` (using the existing
/// `InitPackage`) unless the member already ships one.
///
/// Analogue of `InitPackage`, sharing the "options + write()" shape.
/// This is a proof-of-concept implementation for
/// `swift workspace init`; the POC scope is member
/// scaffolding only — workspace-level `dependencies:` are emitted
/// as an empty array, and users edit `Workspace.swift` afterwards
/// to add deps.
public struct InitWorkspace {
    /// The tools version emitted in the `Workspace.swift` header.
    /// Defaults to the SwiftPM's current tools version.
    public static let newWorkspaceToolsVersion = ToolsVersion.vNext
    // public static let newWorkspaceToolsVersion = ToolsVersion.current

    /// Declaration of a workspace member. `path` is relative to the
    /// workspace root; `packageType` names the shape of the scaffold
    /// (`.library`, `.executable`, etc.) — pass `nil` to skip
    /// scaffolding entirely for a member that's expected to
    /// pre-exist on disk.
    public struct Member {
        public let path: String
        public let packageType: InitPackage.PackageType?

        public init(path: String, packageType: InitPackage.PackageType?) {
            self.path = path
            self.packageType = packageType
        }
    }

    /// Options for creating the workspace scaffold.
    public struct InitWorkspaceOptions {
        public var members: [Member]

        public init(members: [Member]) {
            self.members = members
        }
    }

    let fileSystem: any FileSystem
    let destinationPath: AbsolutePath
    let options: InitWorkspaceOptions
    let progressReporter: ((String) -> Void)?

    public init(
        fileSystem: any FileSystem,
        destinationPath: AbsolutePath,
        options: InitWorkspaceOptions,
        progressReporter: ((String) -> Void)? = nil,
    ) {
        self.fileSystem = fileSystem
        self.destinationPath = destinationPath
        self.options = options
        self.progressReporter = progressReporter
    }

    /// Materializes the workspace on disk. Steps:
    /// 1. Validate all member paths (reject absolute paths).
    /// 2. Refuse to overwrite an existing `Workspace.swift`.
    /// 3. For each member with a `packageType`: create the directory
    ///    (if missing) and invoke `InitPackage` to scaffold its
    ///    `Package.swift`. If the member already has a
    ///    `Package.swift`, log an info line and leave it byte-identical.
    /// 4. Write `Workspace.swift` at the destination.
    public func write() throws {
        for member in self.options.members {
            if member.path.hasPrefix("/") {
                throw InitWorkspaceError.absoluteMemberPath(member.path)
            }
        }
        let manifestPath = self.destinationPath.appending(WorkspaceManifest.filename)
        if self.fileSystem.exists(manifestPath) {
            throw InitWorkspaceError.workspaceManifestAlreadyExists(manifestPath)
        }
        for member in self.options.members {
            let packageType: InitPackage.PackageType = member.packageType ?? .empty
            let memberDir = self.destinationPath.appending(try RelativePath(validating: member.path))
            let memberManifest = memberDir.appending("Package.swift")
            if self.fileSystem.exists(memberManifest) {
                self.progressReporter?(
                    "\(member.path) already has a Package.swift; leaving it alone",
                )
                continue
            }
            if !self.fileSystem.exists(memberDir) {
                try self.fileSystem.createDirectory(memberDir, recursive: true)
            }
            let init_ = try InitPackage(
                name: memberDir.basename,
                options: .init(
                    packageType: packageType,
                    supportedTestingLibraries: [.swiftTesting],
                ),
                destinationPath: memberDir,
                installedSwiftPMConfiguration: .default,
                fileSystem: self.fileSystem,
            )
            init_.progressReporter = self.progressReporter
            try init_.writePackageStructure()
        }
        try self.fileSystem.writeFileContents(manifestPath, string: self.renderManifest())
        self.progressReporter?("Created \(manifestPath.pathString)")
    }

    /// Renders the `Workspace.swift` source using SwiftSyntax so the
    /// output is structurally correct by construction. The tools-version
    /// header is emitted as leading trivia on the `import` declaration
    /// (SwiftPM's tools-version comment is not part of the Swift AST
    /// itself). `dependencies:` is emitted as an empty array for the
    /// POC — users edit the file to add workspace-level dependencies
    /// after scaffolding.
    private func renderManifest() -> String {
        let toolsVersion = Self.newWorkspaceToolsVersion.specification()

        let importDecl = ImportDeclSyntax(
            leadingTrivia: Trivia(pieces: [
                .lineComment(toolsVersion),
                .newlines(1),
            ]),
            importKeyword: .keyword(.import, trailingTrivia: .space),
            path: ImportPathComponentListSyntax([
                ImportPathComponentSyntax(name: .identifier("PackageDescription")),
            ]),
        )

        let workspaceCall = FunctionCallExprSyntax(
            calledExpression: DeclReferenceExprSyntax(baseName: .identifier("Workspace")),
            leftParen: .leftParenToken(trailingTrivia: .newline),
            arguments: LabeledExprListSyntax {
                LabeledExprSyntax(
                    leadingTrivia: .spaces(4),
                    label: .identifier("members"),
                    colon: .colonToken(trailingTrivia: .space),
                    expression: self.buildMembersArray(),
                    trailingComma: .commaToken(trailingTrivia: .newline),
                )
                LabeledExprSyntax(
                    leadingTrivia: .spaces(4),
                    label: .identifier("dependencies"),
                    colon: .colonToken(trailingTrivia: .space),
                    expression: ArrayExprSyntax(elements: ArrayElementListSyntax([])),
                    trailingComma: .commaToken(trailingTrivia: .newline),
                )
            },
            rightParen: .rightParenToken(),
        )

        let workspaceBinding = VariableDeclSyntax(
            leadingTrivia: .newlines(2),
            bindingSpecifier: .keyword(.let, trailingTrivia: .space),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("workspace")),
                    initializer: InitializerClauseSyntax(
                        equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                        value: ExprSyntax(workspaceCall),
                    ),
                ),
            ]),
        )

        let source = SourceFileSyntax(
            statements: CodeBlockItemListSyntax {
                CodeBlockItemSyntax(item: .decl(DeclSyntax(importDecl)))
                CodeBlockItemSyntax(item: .decl(DeclSyntax(workspaceBinding)))
            },
            endOfFileToken: .endOfFileToken(leadingTrivia: .newline),
        )

        return source.description
    }

    /// Builds the `members:` array literal. Empty and non-empty
    /// members produce different-shaped literals: `[]` on one line
    /// versus one entry per line with 8-space indentation matching the
    /// existing hand-written manifests.
    private func buildMembersArray() -> ArrayExprSyntax {
        if self.options.members.isEmpty {
            return ArrayExprSyntax(elements: ArrayElementListSyntax([]))
        }
        var elements: [ArrayElementSyntax] = []
        for member in self.options.members {
            elements.append(
                ArrayElementSyntax(
                    leadingTrivia: .newline + .spaces(8),
                    expression: ExprSyntax(StringLiteralExprSyntax(content: member.path)),
                    trailingComma: .commaToken(),
                ),
            )
        }
        return ArrayExprSyntax(
            leftSquare: .leftSquareToken(),
            elements: ArrayElementListSyntax(elements),
            rightSquare: .rightSquareToken(leadingTrivia: .newline + .spaces(4)),
        )
    }
}
