//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic

public struct ManifestWriter {
    let fileSystem: FileSystem

    public init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }

    public func write(
        _ manifest: BuildManifest,
        at path: AbsolutePath
    ) throws {
        let stream = BufferedOutputByteStream()
        stream.send(
            """
            client:
              name: basic
            tools: {}
            targets:

            """
        )

        for (_, target) in manifest.targets.sorted(by: { $0.key < $1.key }) {
            stream.send("  \(Format.asJSON(target.name)): \(Format.asJSON(target.nodes.map(\.name).sorted()))\n")
        }

        stream.send("default: \(Format.asJSON(manifest.defaultTarget))\n")

        // We need to explicitly configure  the directory structure nodes.
        let directoryStructureNodes = Set(manifest.commands
            .values
            .flatMap{ $0.tool.inputs }
            .filter{ $0.kind == .directoryStructure }
        )

        if !directoryStructureNodes.isEmpty {
            stream.send("nodes:")
        }
        let namesToExclude = [".git", ".build"]
        for node in directoryStructureNodes.sorted(by: { $0.name < $1.name }) {
            stream.send(
                """
                  \(Format.asJSON(node)):
                    is-directory-structure: true
                    content-exclusion-patterns: \(Format.asJSON(namesToExclude))

                """
            )
        }

        stream.send("commands:\n")
        for (_,  command) in manifest.commands.sorted(by: { $0.key < $1.key }) {
            stream.send("  \(Format.asJSON(command.name)):\n")

            let tool = command.tool

            let manifestToolWriter = ManifestToolStream(stream)
            manifestToolWriter["tool"] = tool
            manifestToolWriter["inputs"] = tool.inputs
            manifestToolWriter["outputs"] = tool.outputs

            tool.write(to: manifestToolWriter)

            stream.send("\n")
        }

        try self.fileSystem.writeFileContents(path, bytes: stream.bytes)
    }
}

public final class ManifestToolStream {
    private let stream: OutputByteStream

    fileprivate init(_ stream: OutputByteStream) {
        self.stream = stream
    }

    public subscript(key: String) -> Int {
        get { fatalError() }
        set {
            stream.send("    \(key): \(Format.asJSON(newValue))\n")
        }
    }

    public subscript(key: String) -> String {
        get { fatalError() }
        set {
            stream.send("    \(key): \(Format.asJSON(newValue))\n")
        }
    }

    public subscript(key: String) -> ToolProtocol {
        get { fatalError() }
        set {
            stream.send("    \(key): \(type(of: newValue).name)\n")
        }
    }

    public subscript(key: String) -> AbsolutePath {
         get { fatalError() }
         set {
            stream.send("    \(key): \(Format.asJSON(newValue.pathString))\n")
         }
     }

    public subscript(key: String) -> [AbsolutePath] {
         get { fatalError() }
         set {
            stream.send("    \(key): \(Format.asJSON(newValue.map(\.pathString)))\n")
         }
     }

    public subscript(key: String) -> [Node] {
        get { fatalError() }
        set {
            stream.send("    \(key): \(Format.asJSON(newValue))\n")
        }
    }

    public subscript(key: String) -> Bool {
        get { fatalError() }
        set {
            stream.send("    \(key): \(Format.asJSON(newValue))\n")
        }
    }

    public subscript(key: String) -> [String] {
        get { fatalError() }
        set {
            stream.send("    \(key): \(Format.asJSON(newValue))\n")
        }
    }

    public subscript(key: String) -> [String: String] {
        get { fatalError() }
        set {
            stream.send("    \(key):\n")
            for (key, value) in newValue.sorted(by: { $0.key < $1.key }) {
                stream.send("      \(Format.asJSON(key)): \(Format.asJSON(value))\n")
            }
        }
    }
}

extension Format {
    static func asJSON(_ items: [Node]) -> ByteStreamable {
        return asJSON(items.map { $0.encodingName })
    }

    static func asJSON(_ item: Node) -> ByteStreamable {
        return asJSON(item.encodingName)
    }
}

extension Node {
    fileprivate var encodingName: String {
        switch kind {
        case .virtual, .file:
            return name
        case .directory, .directoryStructure:
            return name + "/"
        }
    }
}
