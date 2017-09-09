/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageModel

public let moduleMapFilename = "module.modulemap"

/// A protocol for targets which might have a modulemap.
protocol ModuleMapProtocol {
    var moduleMapPath: AbsolutePath { get }

    var moduleMapDirectory: AbsolutePath { get }
}

extension CTarget: ModuleMapProtocol {
    var moduleMapDirectory: AbsolutePath {
        return path
    }

    public var moduleMapPath: AbsolutePath {
        return moduleMapDirectory.appending(component: moduleMapFilename)
    }
}

extension ClangTarget: ModuleMapProtocol {
    var moduleMapDirectory: AbsolutePath {
        return includeDir
    }

    public var moduleMapPath: AbsolutePath {
        return moduleMapDirectory.appending(component: moduleMapFilename)
    }
}

/// A modulemap generator for clang targets.
///
/// Modulemap is generated under the following rules provided it is not already present in include directory:
///
/// * "include/foo/foo.h" exists and `foo` is the only directory under include directory.
///    Generates: `umbrella header "/path/to/include/foo/foo.h"`
/// * "include/foo.h" exists and include contains no other directory.
///    Generates: `umbrella header "/path/to/include/foo.h"`
/// *  Otherwise in all other cases.
///    Generates: `umbrella "path/to/include"`
public struct ModuleMapGenerator {

    /// The clang target to operate on.
    private let target: ClangTarget

    /// The file system to be used.
    private var fileSystem: FileSystem

    /// Stream on which warnings will be emitted.
    private let warningStream: OutputByteStream

    public init(
        for target: ClangTarget,
        fileSystem: FileSystem = localFileSystem,
        warningStream: OutputByteStream = stdoutStream
    ) {
        self.target = target
        self.fileSystem = fileSystem
        self.warningStream = warningStream
    }

    public enum ModuleMapError: Swift.Error {
        case unsupportedIncludeLayoutForModule(String, UnsupportedIncludeLayoutType)

        public enum UnsupportedIncludeLayoutType {
            case umbrellaHeaderWithAdditionalNonEmptyDirectories(AbsolutePath, [AbsolutePath])
            case umbrellaHeaderWithAdditionalDirectoriesInIncludeDirectory(AbsolutePath, [AbsolutePath])
            case umbrellaHeaderWithAdditionalFilesInIncludeDirectory(AbsolutePath, [AbsolutePath])
        }
    }

    /// Create the synthesized modulemap, if necessary.
    /// Note: modulemap is not generated for test targets.
    public mutating func generateModuleMap(inDir wd: AbsolutePath) throws {
        assert(target.type == .library)

        // Return if modulemap is already present.
        guard !fileSystem.isFile(target.moduleMapPath) else {
            return
        }

        let includeDir = target.includeDir
        // Warn and return if no include directory.
        guard fileSystem.isDirectory(includeDir) else {
            warningStream <<< ("warning: no include directory found for target '\(target.name)'; " +
                "libraries cannot be imported without public headers")
            warningStream.flush()
            return
        }

        let walked = try fileSystem.getDirectoryContents(includeDir).map({ includeDir.appending(component: $0) })

        let files = walked.filter({ fileSystem.isFile($0) && $0.suffix == ".h" })
        let dirs = walked.filter({ fileSystem.isDirectory($0) })

        let umbrellaHeaderFlat = includeDir.appending(component: target.c99name + ".h")
        if fileSystem.isFile(umbrellaHeaderFlat) {
            guard dirs.isEmpty else {
                throw ModuleMapError.unsupportedIncludeLayoutForModule(
                    target.name,
                    .umbrellaHeaderWithAdditionalNonEmptyDirectories(umbrellaHeaderFlat, dirs))
            }
            try createModuleMap(inDir: wd, type: .header(umbrellaHeaderFlat))
            return
        }
        diagnoseInvalidUmbrellaHeader(includeDir)

        let umbrellaHeader = includeDir.appending(components: target.c99name, target.c99name + ".h")
        if fileSystem.isFile(umbrellaHeader) {
            guard dirs.count == 1 else {
                throw ModuleMapError.unsupportedIncludeLayoutForModule(
                    target.name,
                    .umbrellaHeaderWithAdditionalDirectoriesInIncludeDirectory(umbrellaHeader, dirs))
            }
            guard files.isEmpty else {
                throw ModuleMapError.unsupportedIncludeLayoutForModule(
                    target.name,
                    .umbrellaHeaderWithAdditionalFilesInIncludeDirectory(umbrellaHeader, files))
            }
            try createModuleMap(inDir: wd, type: .header(umbrellaHeader))
            return
        }
        diagnoseInvalidUmbrellaHeader(includeDir.appending(component: target.c99name))

        try createModuleMap(inDir: wd, type: .directory(includeDir))
    }

    /// Warn user if in case target name and c99name are different and there is a
    /// `name.h` umbrella header.
    private func diagnoseInvalidUmbrellaHeader(_ path: AbsolutePath) {
        let umbrellaHeader = path.appending(component: target.c99name + ".h")
        let invalidUmbrellaHeader = path.appending(component: target.name + ".h")
        if target.c99name != target.name && fileSystem.isFile(invalidUmbrellaHeader) {
            warningStream <<< ("warning: \(invalidUmbrellaHeader.asString) should be renamed to " +
                "\(umbrellaHeader.asString) to be used as an umbrella header")
            warningStream.flush()
        }
    }

    private enum UmbrellaType {
        case header(AbsolutePath)
        case directory(AbsolutePath)
    }

    private mutating func createModuleMap(inDir wd: AbsolutePath, type: UmbrellaType) throws {
        let stream = BufferedOutputByteStream()
        stream <<< "module \(target.c99name) {\n"
        switch type {
        case .header(let header):
            stream <<< "    umbrella header \"\(header.asString)\"\n"
        case .directory(let path):
            stream <<< "    umbrella \"\(path.asString)\"\n"
        }
        stream <<< "    export *\n"
        stream <<< "}\n"

        // FIXME: This doesn't belong here.
        try fileSystem.createDirectory(wd, recursive: true)

        let file = wd.appending(component: moduleMapFilename)

        // If the file exists with the identical contents, we don't need to rewrite it.
        // Otherwise, compiler will recompile even if nothing else has changed.
        if let contents = try? localFileSystem.readFileContents(file), contents == stream.bytes {
            return
        }
        try fileSystem.writeFileContents(file, bytes: stream.bytes)
    }
}

extension ModuleMapGenerator.ModuleMapError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unsupportedIncludeLayoutForModule(let (name, problem)):
            return "target '\(name)' failed modulemap generation; \(problem)"
        }
    }
}

extension ModuleMapGenerator.ModuleMapError.UnsupportedIncludeLayoutType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .umbrellaHeaderWithAdditionalNonEmptyDirectories(let (umbrella, dirs)):
            return "umbrella header defined at '\(umbrella.asString)', but directories exist: " +
                dirs.map({ $0.asString }).sorted().joined(separator: ", ") +
                "; consider removing them"
        case .umbrellaHeaderWithAdditionalDirectoriesInIncludeDirectory(let (umbrella, dirs)):
            return "umbrella header defined at '\(umbrella.asString)', but more than one directories exist: " +
                dirs.map({ $0.asString }).sorted().joined(separator: ", ") +
                "; consider reducing them to one"
        case .umbrellaHeaderWithAdditionalFilesInIncludeDirectory(let (umbrella, files)):
            return "umbrella header defined at '\(umbrella.asString)', but files exist:" +
                files.map({ $0.asString }).sorted().joined(separator: ", ") +
                "; consider removing them"
        }
    }
}
