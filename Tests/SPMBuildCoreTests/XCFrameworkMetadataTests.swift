/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import SPMBuildCore
import TSCBasic
import XCTest

final class XCFrameworkMetadataTests: XCTestCase {
    func testParseFramework() throws {
        let fileSystem = InMemoryFileSystem(files: [
            "/Info.plist": ByteString(encodingAsUTF8: """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>AvailableLibraries</key>
                <array>
                    <dict>
                        <key>LibraryIdentifier</key>
                        <string>macos-x86_64</string>
                        <key>LibraryPath</key>
                        <string>MyFramework.framework</string>
                        <key>SupportedArchitectures</key>
                        <array>
                            <string>x86_64</string>
                        </array>
                        <key>SupportedPlatform</key>
                        <string>macos</string>
                    </dict>
                </array>
                <key>CFBundlePackageType</key>
                <string>XFWK</string>
                <key>XCFrameworkFormatVersion</key>
                <string>1.0</string>
            </dict>
            </plist>
            """),
        ])

        let metadata = try XCFrameworkMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        XCTAssertEqual(metadata,
                       XCFrameworkMetadata(libraries: [
                           XCFrameworkMetadata.Library(
                               libraryIdentifier: "macos-x86_64",
                               libraryPath: "MyFramework.framework",
                               headersPath: nil,
                               platform: "macos",
                               architectures: ["x86_64"]
                           ),
                       ]))
    }

    func testParseLibrary() throws {
        let fileSystem = InMemoryFileSystem(files: [
            "/Info.plist": ByteString(encodingAsUTF8: """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>AvailableLibraries</key>
                <array>
                    <dict>
                        <key>LibraryIdentifier</key>
                        <string>macos-x86_64</string>
                        <key>HeadersPath</key>
                        <string>Headers</string>
                        <key>LibraryPath</key>
                        <string>MyLibrary.a</string>
                        <key>SupportedArchitectures</key>
                        <array>
                            <string>x86_64</string>
                        </array>
                        <key>SupportedPlatform</key>
                        <string>macos</string>
                    </dict>
                </array>
                <key>CFBundlePackageType</key>
                <string>XFWK</string>
                <key>XCFrameworkFormatVersion</key>
                <string>1.0</string>
            </dict>
            </plist>
            """),
        ])

        let metadata = try XCFrameworkMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        XCTAssertEqual(metadata,
                       XCFrameworkMetadata(
                           libraries: [
                               XCFrameworkMetadata.Library(
                                   libraryIdentifier: "macos-x86_64",
                                   libraryPath: "MyLibrary.a",
                                   headersPath: "Headers",
                                   platform: "macos",
                                   architectures: ["x86_64"]
                               ),
                           ]))
    }
}
