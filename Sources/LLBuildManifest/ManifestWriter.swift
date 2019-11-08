/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

public struct ManifestWriter {

    let fs: FileSystem

    public init(_ fs: FileSystem = localFileSystem) {
        self.fs = fs
    }

    public func write(
        _ manifest: BuildManifest,
        at path: AbsolutePath
    ) throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            client:
              name: basic
            tools: {}
            targets:\n
            """

        for (_, target) in manifest.targets.sorted(by: { $0.key < $1.key }) {
            stream <<< "  " <<< Format.asJSON(target.name)
            stream <<< ": " <<< Format.asJSON(target.nodes.map{ $0.name }.sorted()) <<< "\n"
        }

        stream <<< "default: " <<< Format.asJSON(manifest.defaultTarget) <<< "\n"

        // We need to explicitly configure  the directory structure nodes.
        let directoryStructureNodes = Set(manifest.commands
            .values
            .flatMap{ $0.tool.inputs }
            .filter{ $0.kind == .directoryStructure }
        )

        if !directoryStructureNodes.isEmpty {
            stream <<< "nodes:\n"
        }
        for node in directoryStructureNodes.sorted(by: { $0.name < $1.name }) {
            stream <<< "  " <<< Format.asJSON(node) <<< ":\n"
            stream <<< "    is-directory-structure: true\n"
        }

        stream <<< "commands:\n"
        for (_,  command) in manifest.commands.sorted(by: { $0.key < $1.key }) {
            stream <<< "  " <<< Format.asJSON(command.name) <<< ":\n"

            let tool = command.tool

            let manifestToolWriter = ManifestToolStream(stream)
            manifestToolWriter["tool"] = tool
            manifestToolWriter["inputs"] = tool.inputs
            manifestToolWriter["outputs"] = tool.outputs

            tool.write(to: manifestToolWriter)

            stream <<< "\n"
        }

        try fs.writeFileContents(path, bytes: stream.bytes)
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
            stream <<< "    \(key): " <<< Format.asJSON(newValue) <<< "\n"
        }
    }

    public subscript(key: String) -> String {
        get { fatalError() }
        set {
            stream <<< "    \(key): " <<< Format.asJSON(newValue) <<< "\n"
        }
    }

    public subscript(key: String) -> ToolProtocol {
        get { fatalError() }
        set {
            stream <<< "    \(key): " <<< type(of: newValue).name <<< "\n"
        }
    }

    public subscript(key: String) -> AbsolutePath {
         get { fatalError() }
         set {
            stream <<< "    \(key): " <<< Format.asJSON(newValue.pathString) <<< "\n"
         }
     }

    public subscript(key: String) -> [AbsolutePath] {
         get { fatalError() }
         set {
            stream <<< "    \(key): " <<< Format.asJSON(newValue.map{$0.pathString}) <<< "\n"
         }
     }

    public subscript(key: String) -> [Node] {
        get { fatalError() }
        set {
            stream <<< "    \(key): " <<< Format.asJSON(newValue) <<< "\n"
        }
    }

    public subscript(key: String) -> Bool {
        get { fatalError() }
        set {
            stream <<< "    \(key): " <<< Format.asJSON(newValue) <<< "\n"
        }
    }

    public subscript(key: String) -> [String] {
        get { fatalError() }
        set {
            stream <<< "    \(key): " <<< Format.asJSON(newValue) <<< "\n"
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
