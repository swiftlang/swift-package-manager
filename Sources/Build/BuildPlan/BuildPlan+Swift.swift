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

import struct Basics.InternalError

import class PackageModel.BinaryModule
import class PackageModel.ClangModule
import class PackageModel.SystemLibraryModule

import PackageGraph
import PackageLoading
import SPMBuildCore

extension BuildPlan {
    func plan(swiftTarget: SwiftModuleBuildDescription) throws {
        // We need to iterate recursive dependencies because Swift compiler needs to see all the targets a target
        // builds against
        for case .module(let dependency, let description) in swiftTarget.recursiveLinkDependencies(using: self) {
            switch dependency.underlying {
            case let underlyingTarget as ClangModule where underlyingTarget.type == .library:
                guard case let .clang(target)? = description else {
                    throw InternalError("unexpected clang target \(underlyingTarget)")
                }
                // Add the path to modulemap of the dependency. Currently we require that all Clang targets have a
                // modulemap but we may want to remove that requirement since it is valid for a target to exist without
                // one. However, in that case it will not be importable in Swift targets. We may want to emit a warning
                // in that case from here.
                guard let moduleMap = target.moduleMap else { break }
                swiftTarget.additionalFlags += [
                    "-Xcc", "-fmodule-map-file=\(moduleMap.pathString)",
                    "-Xcc", "-I", "-Xcc", target.clangTarget.includeDir.pathString,
                ]
            case let target as SystemLibraryModule:
                swiftTarget.additionalFlags += ["-Xcc", "-fmodule-map-file=\(target.moduleMapPath.pathString)"]
                swiftTarget.additionalFlags += try pkgConfig(for: target).cFlags
            case let target as BinaryModule:
                switch target.kind {
                case .unknown:
                    break
                case .artifactsArchive:
                    let libraries = try self.parseLibraryArtifactsArchive(for: target, triple: swiftTarget.buildParameters.triple)
                    for library in libraries {
                        library.headersPaths.forEach {
                            swiftTarget.additionalFlags += ["-I", $0.pathString, "-Xcc", "-I", "-Xcc", $0.pathString]
                        }
                        if let moduleMapPath = library.moduleMapPath {
                            // We need to pass the module map if there is one. If there is none Swift cannot import it but
                            // this might still be valid
                            swiftTarget.additionalFlags += ["-Xcc", "-fmodule-map-file=\(moduleMapPath)"]
                        }

                        swiftTarget.libraryBinaryPaths.insert(library.libraryPath)
                    }
                case .xcframework:
                    let libraries = try self.parseXCFramework(for: target, triple: swiftTarget.buildParameters.triple)
                    for library in libraries {
                        library.headersPaths.forEach {
                            swiftTarget.additionalFlags += ["-I", $0.pathString, "-Xcc", "-I", "-Xcc", $0.pathString]
                        }
                        swiftTarget.libraryBinaryPaths.insert(library.libraryPath)
                    }
                }
            default:
                break
            }
        }
    }
}
