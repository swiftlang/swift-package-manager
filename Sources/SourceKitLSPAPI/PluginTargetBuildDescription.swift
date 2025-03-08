//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import Basics
import PackageGraph
internal import PackageLoading
internal import PackageModel

struct PluginTargetBuildDescription: BuildTarget {
    private let target: ResolvedModule
    private let toolsVersion: ToolsVersion
    private let toolchain: any Toolchain
    let isPartOfRootPackage: Bool
    var isTestTarget: Bool { false }

    init(target: ResolvedModule, toolsVersion: ToolsVersion, toolchain: any Toolchain, isPartOfRootPackage: Bool) {
        assert(target.type == .plugin)
        self.target = target
        self.toolsVersion = toolsVersion
        self.toolchain = toolchain
        self.isPartOfRootPackage = isPartOfRootPackage
    }

    var sources: [SourceItem] {
        return target.sources.paths.map {
          SourceItem(sourceFile: $0.asURL, outputFile: nil)
        }
    }

    var headers: [URL] { [] }

    var resources: [URL] {
        return target.underlying.resources.map(\.path.asURL)
    }

    var ignored: [URL] {
        return target.underlying.ignored.map(\.asURL)
    }

    var others: [URL] {
        return target.underlying.others.map(\.asURL)
    }

    var name: String {
        return target.name
    }

    var compiler: BuildTargetCompiler { .swift }

    var destination: BuildDestination {
        // Plugins are always built for the host.
        .host
    }

    var outputPaths: [URL] {
        get throws {
            struct NotSupportedError: Error, CustomStringConvertible {
                var description: String { "Getting output paths for a plugin target is not supported" }
            }
            throw NotSupportedError()
        }
    }

    func compileArguments(for fileURL: URL) throws -> [String] {
        // FIXME: This is very odd and we should clean this up by merging `ManifestLoader` and `DefaultPluginScriptRunner` again.
        var args = ManifestLoader.interpreterFlags(for: self.toolsVersion, toolchain: toolchain)
        // Note: we ignore the `fileURL` here as the expectation is that we get a commandline for the entire target in case of Swift. Plugins are always assumed to only consist of Swift files.
        args += try sources.map { try $0.sourceFile.filePath }
        return args
    }
}

fileprivate enum FilePathError: Error, CustomStringConvertible {
  case noFileSystemRepresentation(URL)
  case noFileURL(URL)

  var description: String {
    switch self {
    case .noFileSystemRepresentation(let url):
      return "\(url.description) cannot be represented as a file system path"
    case .noFileURL(let url):
      return "\(url.description) is not a file URL"
    }
  }
}

fileprivate extension URL {
  /// Assuming that this is a file URL, the path with which the file system refers to the file. This is similar to
  /// `path` but has two differences:
  /// - It uses backslashes as the path separator on Windows instead of forward slashes
  /// - It throws an error when called on a non-file URL.
  ///
  /// `filePath` should generally be preferred over `path` when dealing with file URLs.
  var filePath: String {
    get throws {
      guard self.isFileURL else {
        throw FilePathError.noFileURL(self)
      }
      return try self.withUnsafeFileSystemRepresentation { buffer in
        guard let buffer else {
          throw FilePathError.noFileSystemRepresentation(self)
        }
        return String(cString: buffer)
      }
    }
  }
}
