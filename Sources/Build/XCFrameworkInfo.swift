/*
This source file is part of the Swift.org open source project

Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import PackageModel
import SPMBuildCore
import Foundation

public struct XCFrameworkInfo: Equatable {
    public struct Library: Equatable {
        public let libraryIdentifier: String
        public let libraryPath: String
        public let headersPath: String?
        public let platform: String
        public let architectures: [String]

        public init(
            libraryIdentifier: String,
            libraryPath: String,
            headersPath: String?,
            platform: String,
            architectures: [String]
        ) {
            self.libraryIdentifier = libraryIdentifier
            self.libraryPath = libraryPath
            self.headersPath = headersPath
            self.platform = platform
            self.architectures = architectures
        }
    }

    public let libraries: [Library]

    public init(libraries: [Library]) {
        self.libraries = libraries
    }
}

extension XCFrameworkInfo {
    public init?(path: AbsolutePath, diagnostics: DiagnosticsEngine, fileSystem: FileSystem) {
        guard fileSystem.exists(path) else {
            diagnostics.emit(error: "missing XCFramework Info.plist at '\(path)'")
            return nil
        }

        do {
            let plistBytes = try fileSystem.readFileContents(path)

            let decoder = PropertyListDecoder()
            self = try plistBytes.withData({ data in
                try decoder.decode(XCFrameworkInfo.self, from: data)
            })
        } catch {
            diagnostics.emit(error: "failed parsing XCFramework Info.plist at '\(path)': \(error)")
            return nil
        }
    }
}

extension XCFrameworkInfo: Decodable {
    enum CodingKeys: String, CodingKey {
        case libraries = "AvailableLibraries"
    }
}

extension Triple.Arch: Decodable { }
extension XCFrameworkInfo.Library: Decodable {
    enum CodingKeys: String, CodingKey {
        case libraryIdentifier = "LibraryIdentifier"
        case libraryPath = "LibraryPath"
        case headersPath = "HeadersPath"
        case platform = "SupportedPlatform"
        case architectures = "SupportedArchitectures"
    }
}
