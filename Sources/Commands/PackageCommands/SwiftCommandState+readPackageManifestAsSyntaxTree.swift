//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import CoreCommands
import Foundation
import PackageGraph
import PackageModel
import SwiftParser
import SwiftSyntax
import TSCBasic
import Workspace

extension SwiftCommandState {
    /// Read the package manifest of the current package on disk and parse it as a syntax tree.
    func readPackageManifestAsSyntaxTree() throws -> (syntax: SourceFileSyntax, path: Basics.AbsolutePath) {
        guard let packagePath = try getWorkspaceRoot().packages.first else {
            throw StringError("unknown package")
        }

        let manifestPath = packagePath.appending(component: Manifest.filename)
        let manifestContents: ByteString
        do {
            manifestContents = try getActiveWorkspace().fileSystem.readFileContents(manifestPath)
        } catch {
            throw StringError("cannot find package manifest in \(manifestPath)")
        }

        let sourceFileSyntax = manifestContents.withData { data in
            data.withUnsafeBytes { buffer in
                buffer.withMemoryRebound(to: UInt8.self) { buffer in
                    Parser.parse(source: buffer)
                }
            }
        }
        return (sourceFileSyntax, manifestPath)
    }
}
