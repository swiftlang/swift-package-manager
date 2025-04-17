//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// An `Archiver` that handles multiple formats by delegating to other existing archivers each dedicated to its own
/// format.
public struct UniversalArchiver: Archiver {
    public let supportedExtensions: Set<String>

    /// Errors specific to the implementation of ``UniversalArchiver``.
    enum Error: Swift.Error {
        case unknownFormat([String], AbsolutePath)
        case noFileNameExtension(AbsolutePath)

        var description: String {
            switch self {
            case .unknownFormat(let ext, let path):
                return "unknown format with extension \(ext.joined(separator: ".")) at path `\(path)`"
            case .noFileNameExtension(let path):
                return "file at path `\(path)` has no extension to detect archival format from"
            }
        }
    }

    /// A dictionary that maps file extension strings to archiver instances that supports these extensions.
    private let formatMapping: [String: any Archiver]

    public init(_ fileSystem: any FileSystem, _ cancellator: Cancellator? = nil) {
        var formatMapping = [String: any Archiver]()
        var supportedExtensions = Set<String>()

        for archiver in [
            ZipArchiver(fileSystem: fileSystem, cancellator: cancellator),
            TarArchiver(fileSystem: fileSystem, cancellator: cancellator),
        ] as [any Archiver] {
            supportedExtensions.formUnion(archiver.supportedExtensions)
            for ext in archiver.supportedExtensions {
                formatMapping[ext] = archiver
            }
        }

        self.formatMapping = formatMapping
        self.supportedExtensions = supportedExtensions
    }

    private func archiver(for archivePath: AbsolutePath) throws -> any Archiver {
        guard var extensions = archivePath.allExtensions, extensions.count > 0 else {
            throw Error.noFileNameExtension(archivePath)
        }

        // None of the archivers support extensions with more than 2 extension components
        if extensions.count > 2 {
            extensions = extensions.suffix(2)
        }

        if let archiver = self.formatMapping[extensions.joined(separator: ".")] {
            return archiver
        } else if let lastExtension = extensions.last, let archiver = self.formatMapping[lastExtension] {
            return archiver
        } else {
            throw Error.unknownFormat(extensions, archivePath)
        }
    }

    public func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping @Sendable (Result<Void, Swift.Error>) -> Void
    ) {
        do {
            let archiver = try archiver(for: archivePath)
            archiver.extract(from: archivePath, to: destinationPath, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    public func compress(
        directory: AbsolutePath,
        to destinationPath: AbsolutePath
    ) async throws {
        let archiver = try archiver(for: destinationPath)
        try await archiver.compress(directory: directory, to: destinationPath)
    }

    public func validate(
        path: AbsolutePath,
        completion: @escaping @Sendable (Result<Bool, Swift.Error>) -> Void
    ) {
        do {
            let archiver = try archiver(for: path)
            archiver.validate(path: path, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }
}
