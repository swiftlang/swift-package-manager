import Foundation
import Subprocess

public class ASTNode: Decodable {
    var kind: String?
    var name: String?
    var tagUsed: String?
    var type: ASTType?
    var inner: [ASTNode]?
    
    struct ASTType: Decodable {
        var qualType: String
    }
}

public func loadAST(headerPaths: [URL], headerFile: URL) async throws -> ASTNode {
    var clangArgs: [String] = [
        "-Xclang", "-ast-dump=json", "-fsyntax-only",
        "-I", headerFile.deletingLastPathComponent().path
    ]

    for headerPath in headerPaths {
        clangArgs += ["-I", headerPath.path]
    }
    clangArgs += [headerFile.path]

    let clangOutput = try await run(.name("clang"), arguments: .init(clangArgs), output: .data(limit: .max)).standardOutput
    return try JSONDecoder().decode(ASTNode.self, from: clangOutput)
}
