import Foundation
import SwiftBridging

public func run() throws {
/*    let libraryName = CommandLine.arguments[1]
    let libraryDir = CommandLine.arguments[2]
    let includeDir = CommandLine.arguments[3]
    let header = CommandLine.arguments[4]
    let outputFile = URL(fileURLWithPath: CommandLine.arguments[5])

    // Synthesize interface
    let findSDK = TSCBasic.Process(args: "xcrun", "--show-sdk-path")
    try findSDK.launch()
    let sdkPath = try findSDK.waitUntilExit().utf8Output().trimmingCharacters(in: .newlines)
    
    var synthArgs: [String] = [
        "xcrun", "swift-synthesize-interface", "-I", libraryDir,
        "-module-name", libraryName,
        "-target", "arm64-apple-macos15",
        "-sdk", sdkPath
    ]
    if includeDir == "error" {
        fatalError("no include dir")
    } else if includeDir.contains("xcframework") {
        synthArgs += ["-F", includeDir]
    } else {
        synthArgs += ["-I", includeDir]
    }

    let synth = TSCBasic.Process(arguments: synthArgs, outputRedirection: .collect(redirectStderr: true))
    try synth.launch()
    let interface = try synth.waitUntilExit().utf8Output()

    let tree = Parser.parse(source: interface)

    var clangArgs: [String] = [
        "clang", "-Xclang", "-ast-dump=json", "-fsyntax-only",
        "-I", libraryDir,
    ]
    if includeDir.contains("xcframework") {
        synthArgs += ["-F", includeDir]
    } else {
        synthArgs += ["-I", includeDir]
    }
    clangArgs += ["\(libraryDir)/\(header)"]
    let clang = TSCBasic.Process(arguments: clangArgs, outputRedirection: .collect(redirectStderr: true))
    try clang.launch()
    let clangOutput = try Data(clang.waitUntilExit().output.get())
    let ast = try JSONDecoder().decode(ASTNode.self, from: clangOutput)
    
    guard let nodes = ast.inner else {
        print("Empty AST")
        return
    }
    
    let opaqueTypes: [String] = nodes.compactMap({
        guard $0.kind == "RecordDecl",
              $0.tagUsed == "struct",
              $0.inner == nil,
              let name = $0.name
        else {
            return nil
        }
        return name
    }).sorted()
    
    let functions: [ASTNode] = nodes.compactMap {
        guard $0.kind == "FunctionDecl" else {
            return nil
        }
        return $0
    }
    
    class FunctionCollector: SyntaxVisitor {
        var functions: [String: FunctionDeclSyntax] = [:]

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            functions[node.name.text] = node
            return .skipChildren
        }
    }
    let collector = FunctionCollector(viewMode: .all)
    collector.walk(tree)
    
    guard let createWindow = collector.functions["SDL_DestroyWindow"] else {
        fatalError()
    }
    for param in createWindow.signature.parameterClause.parameters {
        let label = param.secondName?.text ??  param.firstName.text
        let type = param.type.description
        print(label, type)
    }
    if let returnType = createWindow.signature.returnClause?.type.description {
        print("->", returnType)
    }

    let gen = ""
    try gen.data(using: .utf8)?.write(to: outputFile)

    let clangFile = outputFile.deletingLastPathComponent().appending(path: "clang.ast")
    try clangOutput.write(to: clangFile)
    
    let interfaceFile = outputFile.deletingLastPathComponent().appending(path: "interface.out")
    try interface.data(using: .utf8)?.write(to: interfaceFile)
*/

    print("Done!")
}
