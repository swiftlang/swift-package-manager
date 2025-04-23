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

import Basics
import CoreCommands
import Foundation
import TSCBasic

#if canImport(FoundationXML)
import FoundationXML
#endif
import class PackageModel.Manifest

/// A bare minimum loader for Xcode workspaces.
///
/// Warning: This is only useful for debugging workspaces that contain Swift packages.
public struct XcodeWorkspaceLoader: WorkspaceLoader {

    /// The parsed location.
    private struct Location {
        /// The kind of location.
        enum Kind: String {
            case absolute
            case group
        }

        var kind: Kind
        var path: String
    }

    private let fileSystem: FileSystem
    private let observabilityScope: ObservabilityScope

    public init(fileSystem: FileSystem, observabilityScope: ObservabilityScope) {
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
    }

    /// Load the given workspace and return the file ref paths from it.
    public func load(workspace: Basics.AbsolutePath) throws -> [Basics.AbsolutePath] {
        let path = workspace.appending("contents.xcworkspacedata")
        let contents: Data = try self.fileSystem.readFileContents(path)

        let delegate = ParserDelegate(observabilityScope: self.observabilityScope)
        let parser = XMLParser(data: contents)
        parser.delegate = delegate
        if !parser.parse() {
            throw StringError("unable to load file refs from \(path)")
        }

        /// Convert the parsed result into absolute paths.
        var result: [Basics.AbsolutePath] = []
        for location in delegate.locations {
            let path: Basics.AbsolutePath

            switch location.kind {
            case .absolute:
                path = try AbsolutePath(validating: location.path)
            case .group:
                path = try AbsolutePath(validating: location.path, relativeTo: workspace.parentDirectory)
            }

            if self.fileSystem.exists(path.appending(component: Manifest.filename)) {
                result.append(path)
            } else {
                self.observabilityScope.emit(warning: "ignoring non-package fileref \(path)")
            }
        }
        return result
    }

    /// Parser delegate for the workspace.
    private class ParserDelegate: NSObject, XMLParserDelegate {
        var locations: [Location] = []

        let observabilityScope: ObservabilityScope

        init(observabilityScope: ObservabilityScope) {
            self.observabilityScope = observabilityScope
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String : String] = [:]
        ) {
            guard elementName == "FileRef" else { return }
            guard let location = attributeDict["location"] else { return }

            let splitted = location.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard splitted.count == 2 else {
                self.observabilityScope.emit(warning: "location split count is not two: \(splitted)")
                return
            }
            guard let kind = Location.Kind(rawValue: splitted[0]) else {
                self.observabilityScope.emit(warning: "unknown kind \(splitted[0]) for location \(location)")
                return
            }

            locations.append(Location(kind: kind, path: splitted[1]))
        }
    }
}
