//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Basics
import Testing

private struct SwiftPMTests {
    @Test(
        .requireSwift6_2,
        .requireHostOS(.linux)
    )
    func libraryEvolutionLinuxXCFramework() async throws {
        try await fixture(name: "Miscellaneous/LibraryEvolutionLinuxXCF") { fixturePath in
            let swiftFramework = "SwiftFramework"
            try await withTemporaryDirectory(removeTreeOnDeinit: false) { tmpDir in
                let scratchPath = tmpDir.appending(component: ".build")
                try await executeSwiftBuild(
                    fixturePath.appending(component: swiftFramework),
                    configuration: .debug,
                    extraArgs: ["--scratch-path", scratchPath.pathString],
                    buildSystem: .native
                )

                #if arch(arm64)
                let arch = "aarch64"
                #elseif arch(x86_64)
                let arch = "x86_64"
                #endif

                let platform = "linux"
                let libraryExtension = "so"

                let xcframeworkPath = fixturePath.appending(
                    components: "TestBinary",
                    "\(swiftFramework).xcframework"
                )
                let libraryName = "lib\(swiftFramework).\(libraryExtension)"
                let artifactsPath = xcframeworkPath.appending(component: "\(platform)-\(arch)")

                try localFileSystem.createDirectory(artifactsPath, recursive: true)

                try localFileSystem.copy(
                    from: scratchPath.appending(components: "debug", libraryName),
                    to: artifactsPath.appending(component: libraryName)
                )

                try localFileSystem.copy(
                    from: scratchPath.appending(components: "debug", "Modules", "\(swiftFramework).swiftinterface"),
                    to: artifactsPath.appending(component: "\(swiftFramework).swiftinterface")
                )

                try localFileSystem.writeFileContents(
                    xcframeworkPath.appending(component: "Info.plist"),
                    string: """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                    <plist version="1.0">
                    <dict>
                        <key>AvailableLibraries</key>
                        <array>
                            <dict>
                                <key>BinaryPath</key>
                                <string>\(libraryName)</string>
                                <key>LibraryIdentifier</key>
                                <string>\(platform)-\(arch)</string>
                                <key>LibraryPath</key>
                                <string>\(libraryName)</string>
                                <key>SupportedArchitectures</key>
                                <array>
                                    <string>\(arch)</string>
                                </array>
                                <key>SupportedPlatform</key>
                                <string>\(platform)</string>
                            </dict>
                        </array>
                        <key>CFBundlePackageType</key>
                        <string>XFWK</string>
                        <key>XCFrameworkFormatVersion</key>
                        <string>1.0</string>
                    </dict>
                    </plist>
                    """
                )
            }

            let packagePath = fixturePath.appending(component: "TestBinary")
            let scratchPath = packagePath.appending(component: ".build-test")
            let runOutput = try await executeSwiftRun(
                packagePath, "TestBinary",
                extraArgs: [
                    "--scratch-path", scratchPath.pathString, "--experimental-xcframeworks-on-linux",
                ],
                buildSystem: .native
            )
            #expect(!runOutput.stderr.contains("error:"))
            #expect(runOutput.stdout.contains("Latest Framework with LibraryEvolution version: v2"))
        }
    }
}
