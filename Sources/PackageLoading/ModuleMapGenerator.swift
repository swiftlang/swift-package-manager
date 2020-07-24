/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import PackageModel

public let moduleMapFilename = "module.modulemap"

/// A protocol for targets which might have a modulemap.
protocol ModuleMapProtocol {
    var moduleMapPath: AbsolutePath { get }

    var moduleMapDirectory: AbsolutePath { get }
}

extension SystemLibraryTarget: ModuleMapProtocol {
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
/// * "include/foo/foo.h" exists and `foo` is the only directory under the "include" directory, and the "include" directory contains no header files:
///    Generates: `umbrella header "/path/to/include/foo/foo.h"`
/// * "include/foo.h" exists and "include" contains no other subdirectory:
///    Generates: `umbrella header "/path/to/include/foo.h"`
/// *  Otherwise, if the "include" directory only contains header files and no other subdirectory:
///    Generates: `umbrella "path/to/include"`
public struct ModuleMapGenerator {

    /// The clang target to operate on.
    private let target: ClangTarget

    /// The file system to be used.
    private var fileSystem: FileSystem

    /// Where to emit any warnings and errors.
    private let diagnostics: DiagnosticsEngine

    public init(
        for target: ClangTarget,
        fileSystem: FileSystem = localFileSystem,
        diagnostics: DiagnosticsEngine
    ) {
        self.target = target
        self.fileSystem = fileSystem
        self.diagnostics = diagnostics
    }

    /// Generates a module map based on the layout of the target's public headers, or does nothing if an error occurs or no module map is appropriate.  Any diagnostics are added to the receiver's diagnostics engine.
    public mutating func generateModuleMap(inDir wd: AbsolutePath) throws {
        assert(target.type == .library)

        // Do nothing if modulemap is already present.
        guard !fileSystem.isFile(target.moduleMapPath) else {
            return
        }

        let includeDir = target.includeDir
        // Warn and return if there's no include directory.
        guard fileSystem.isDirectory(includeDir) else {
            diagnostics.emit(warning: "no include directory found for target '\(target.name)'; libraries cannot be imported without public headers")
            return
        }

        let walked = try fileSystem.getDirectoryContents(includeDir).map({ includeDir.appending(component: $0) })

        let files = walked.filter({ fileSystem.isFile($0) && $0.suffix == ".h" })
        let dirs = walked.filter({ fileSystem.isDirectory($0) })

        // If 'include/ModuleName.h' exists, then use it as the umbrella header (this is case 2 at https://github.com/apple/swift-package-manager/blob/master/Documentation/Usage.md#creating-c-language-targets).
        let umbrellaHeaderFlat = includeDir.appending(component: target.c99name + ".h")
        if fileSystem.isFile(umbrellaHeaderFlat) {
            // In this case, 'include' is expected to contain no subdirectories.
            guard dirs.isEmpty else {
                diagnostics.emit(error: "target '\(target.name)' failed modulemap generation: umbrella header found at '\(umbrellaHeaderFlat)', but directories exist next to it: \(dirs.map({ $0.description }).sorted().joined(separator: ", ")); consider removing them")
                return
            }
            try createModuleMap(inDir: wd, type: .header(umbrellaHeaderFlat))
            return
        }
        diagnoseInvalidUmbrellaHeader(includeDir)

        // If 'include/ModuleName/ModuleName.h' exists, then use it as the umbrella header (this is case 1 at Documentation/Usage.md#creating-c-language-targets).
        let umbrellaHeader = includeDir.appending(components: target.c99name, target.c99name + ".h")
        if fileSystem.isFile(umbrellaHeader) {
            // In this case, 'include' is expected to contain no subdirectories other than 'ModuleName', and no header files.
            guard dirs.count == 1 else {
                diagnostics.emit(error: "target '\(target.name)' failed modulemap generation: umbrella header found at '\(umbrellaHeader)', but more than one directory exists next to its parent directory: \(dirs.map({ $0.description }).sorted().joined(separator: ", ")); consider reducing them to one")
                return
            }
            guard files.isEmpty else {
                diagnostics.emit(error: "target '\(target.name)' failed modulemap generation: umbrella header found at '\(umbrellaHeader)', but additional header files exist: \((files.map({ $0.description }).sorted().joined(separator: ", "))); consider reducing them to one")
                return
            }
            try createModuleMap(inDir: wd, type: .header(umbrellaHeader))
            return
        }
        diagnoseInvalidUmbrellaHeader(includeDir.appending(component: target.c99name))

        // Otherwise, if 'include' contains only header files and no subdirectories, use it as the umbrella directory (this is case 3 at https://github.com/apple/swift-package-manager/blob/master/Documentation/Usage.md#creating-c-language-targets).
        if files.count == walked.count {
            try createModuleMap(inDir: wd, type: .directory(includeDir))
            return
        }
        
        // Otherwise, the target's public headers are considered to be incompatible with modules.  Per the original design, an umbrella directory is still created for them.  This is will lead to build failures if those headers are included and they are not compatible with modules.  A future evolution proposal should revisit these semantics.
        try createModuleMap(inDir: wd, type: .directory(includeDir))
    }

    /// Warn user if in case target name and c99name are different and there is a
    /// `name.h` umbrella header.
    private func diagnoseInvalidUmbrellaHeader(_ path: AbsolutePath) {
        let umbrellaHeader = path.appending(component: target.c99name + ".h")
        let invalidUmbrellaHeader = path.appending(component: target.name + ".h")
        if target.c99name != target.name && fileSystem.isFile(invalidUmbrellaHeader) {
            diagnostics.emit(warning: "\(invalidUmbrellaHeader) should be renamed to \(umbrellaHeader) to be used as an umbrella header")
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
            stream <<< "    umbrella header \"\(header.pathString)\"\n"
        case .directory(let path):
            stream <<< "    umbrella \"\(path.pathString)\"\n"
        }
        stream <<< "    export *\n"
        stream <<< "}\n"

        // FIXME: This doesn't belong here.
        try fileSystem.createDirectory(wd, recursive: true)

        let file = wd.appending(component: moduleMapFilename)

        // If the file exists with the identical contents, we don't need to rewrite it.
        // Otherwise, compiler will recompile even if nothing else has changed.
        if let contents = try? fileSystem.readFileContents(file), contents == stream.bytes {
            return
        }
        try fileSystem.writeFileContents(file, bytes: stream.bytes)
    }
}
