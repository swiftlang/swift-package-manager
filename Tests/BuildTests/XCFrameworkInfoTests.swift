/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Build
import TSCBasic

final class XCFrameworkInfoTests: XCTestCase {
    func testParseFramework() {
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
                """)
        ])

        let diagnostics = DiagnosticsEngine()
        guard let xcFrameworkInfo = XCFrameworkInfo(
            path: AbsolutePath("/Info.plist"),
            diagnostics: diagnostics,
            fileSystem: fileSystem
        ) else {
            XCTFail("fail parsing")
            return
        }

        XCTAssert(!diagnostics.hasErrors)
        XCTAssertEqual(xcFrameworkInfo, XCFrameworkInfo(libraries: [
            XCFrameworkInfo.Library(
                libraryIdentifier: "macos-x86_64",
                libraryPath: "MyFramework.framework",
                headersPath: nil,
                platform: "macos",
                architectures: ["x86_64"]
            )
        ]))
    }

    func testParseLibrary() {
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
                """)
        ])

        let diagnostics = DiagnosticsEngine()
        guard let xcFrameworkInfo = XCFrameworkInfo(
            path: AbsolutePath("/Info.plist"),
            diagnostics: diagnostics,
            fileSystem: fileSystem
        ) else {
            XCTFail("fail parsing")
            return
        }

        XCTAssert(!diagnostics.hasErrors)
        XCTAssertEqual(xcFrameworkInfo, XCFrameworkInfo(libraries: [
            XCFrameworkInfo.Library(
                libraryIdentifier: "macos-x86_64",
                libraryPath: "MyLibrary.a",
                headersPath: "Headers",
                platform: "macos",
                architectures: ["x86_64"]
            )
        ]))
    }
}
