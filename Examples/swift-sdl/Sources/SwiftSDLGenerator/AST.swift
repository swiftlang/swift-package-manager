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
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

public class ASTNode: Codable {
    var kind: String?
    var name: String?
    var tagUsed: String?
    var type: ASTType?
    var inner: [ASTNode]?
    
    struct ASTType: Codable {
        var qualType: String
    }
}

// Utility to create a clang AST from the module's umbrella header file
public func loadAST(headerPaths: [FilePath], headerFile: FilePath) async throws -> ASTNode {
    var clangArgs: [String] = [
        "-Xclang", "-ast-dump=json", "-fsyntax-only",
    ]

    for headerPath in headerPaths {
        clangArgs += ["-I", headerPath.string]
    }
    clangArgs += [headerFile.string]

    let clangOutput = try await run(
        .name("clang"), 
        arguments: .init(clangArgs),
        environment: .inherit.updating(["DEVELOPER_DIR": "/Applications/Xcode.app"]),
        output: .data(limit: .max),
        error: .currentStandardError).standardOutput
    return try JSONDecoder().decode(ASTNode.self, from: clangOutput)
}
