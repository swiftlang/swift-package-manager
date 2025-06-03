//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import BinarySymbols
import CoreCommands
import Foundation
import PackageModel
import SPMBuildCore
import Workspace

import struct TSCBasic.StringError

struct AuditBinaryArtifact: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        commandName: "experimental-audit-binary-artifact",
        abstract: "Audit a static library binary artifact for undefined symbols."
    )

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Argument(help: "The absolute or relative path to the binary artifact.")
    var path: AbsolutePath

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        let hostToolchain = try swiftCommandState.getHostToolchain()
        let clang = try hostToolchain.getClangCompiler()
        let objdump = try hostToolchain.getLLVMObjdump()
        let hostTriple = try Triple.getHostTriple(
            usingSwiftCompiler: hostToolchain.swiftCompilerPath)
        let fileSystem = swiftCommandState.fileSystem

        guard !(hostTriple.isDarwin() || hostTriple.isWindows()) else {
            throw StringError(
                "experimental-audit-binary-artifact is not supported on Darwin and Windows platforms."
            )
        }

        var hostDefaultSymbols = ReferencedSymbols()
        let symbolProvider = LLVMObjdumpSymbolProvider(objdumpPath: objdump)
        for binary in try await detectDefaultObjects(
            clang: clang, fileSystem: fileSystem, hostTriple: hostTriple)
        {
            try await symbolProvider.symbols(
                for: binary, symbols: &hostDefaultSymbols, recordUndefined: false)
        }

        let extractedArtifact = try await extractArtifact(
            fileSystem: fileSystem, scratchDirectory: swiftCommandState.scratchDirectory)

        guard
            let artifactKind = try Workspace.BinaryArtifactsManager.deriveBinaryArtifactKind(
                fileSystem: fileSystem,
                path: extractedArtifact,
                observabilityScope: swiftCommandState.observabilityScope
            )
        else {
            throw StringError("Invalid binary artifact provided at \(path)")
        }

        let module = BinaryModule(
            name: path.basenameWithoutExt, kind: artifactKind, path: extractedArtifact,
            origin: .local)
        for library in try module.parseLibraryArtifactArchives(
            for: hostTriple, fileSystem: fileSystem)
        {
            var symbols = hostDefaultSymbols
            try await symbolProvider.symbols(for: library.libraryPath, symbols: &symbols)

            guard symbols.undefined.isEmpty else {
                print(
                    "Invalid artifact binary \(library.libraryPath.pathString), found undefined symbols:"
                )
                for name in symbols.undefined {
                    print("- \(name)")
                }
                throw ExitCode(1)
            }
        }

        print(
            "Artifact is safe to use on the platforms runtime compatible with triple: \(hostTriple.tripleString)"
        )
    }

    private func extractArtifact(fileSystem: any FileSystem, scratchDirectory: AbsolutePath)
        async throws -> AbsolutePath
    {
        let archiver = UniversalArchiver(fileSystem)

        guard let lastPathComponent = path.components.last,
            archiver.isFileSupported(lastPathComponent)
        else {
            let supportedExtensionList = archiver.supportedExtensions.joined(separator: ", ")
            throw StringError(
                "unexpected file type; supported extensions are: \(supportedExtensionList)")
        }

        // Ensure that the path with the accepted extension is a file.
        guard fileSystem.isFile(path) else {
            throw StringError("file not found at path: \(path.pathString)")
        }

        let archiveDirectory = scratchDirectory.appending(
            components: "artifact-auditing",
            path.basenameWithoutExt, UUID().uuidString
        )
        try fileSystem.forceCreateDirectory(at: archiveDirectory)

        try await archiver.extract(from: path, to: archiveDirectory)

        let artifacts = try fileSystem.getDirectoryContents(archiveDirectory)
            .map { archiveDirectory.appending(component: $0) }
            .filter {
                fileSystem.isDirectory($0)
                    && $0.extension == BinaryModule.Kind.artifactsArchive(types: []).fileExtension
            }

        guard artifacts.count == 1 else {
            throw StringError("Could not find an artifact bundle in the archive")
        }

        return artifacts.first!
    }
}
