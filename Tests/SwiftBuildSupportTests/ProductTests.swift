//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing
import Foundation
import _InternalTestSupport

// Tests which rely on implementation details of the build system's directory layout to verify outputs are correct.
// These are fairly susceptible to breaking when implementation details change, so should be extended sparingly.
@Suite
struct ProductTests {
    @Test
    func materializedStaticProducts() async throws {
        try await fixture(name: "Miscellaneous/Simple") { fixturePath in
            try await executeSwiftBuild(fixturePath, buildSystem: .swiftbuild)
            let productsSubDirectory: String
            let expectedProductName: String
            switch try ProcessInfo.processInfo.hostOperatingSystem() {
            case .macOS:
                productsSubDirectory = "Debug"
                expectedProductName = "libFoo.a"
            case .iOS:
                productsSubDirectory = "Debug-iphoneos"
                expectedProductName = "libFoo.a"
            case .tvOS:
                productsSubDirectory = "Debug-appletvos"
                expectedProductName = "libFoo.a"
            case .watchOS:
                productsSubDirectory = "Debug-watchos"
                expectedProductName = "libFoo.a"
            case .visionOS:
                productsSubDirectory = "Debug-xros"
                expectedProductName = "libFoo.a"
            case .windows:
                productsSubDirectory = "Debug-windows"
                expectedProductName = "Foo.objlib"
            case .linux:
                productsSubDirectory = "Debug-linux"
                expectedProductName = "libFoo.a"
            case .freebsd:
                productsSubDirectory = "Debug-freebsd"
                expectedProductName = "libFoo.a"
            case .openbsd:
                productsSubDirectory = "Debug-openbsd"
                expectedProductName = "libFoo.a"
            case .android:
                productsSubDirectory = "Debug-android"
                expectedProductName = "libFoo.a"
            case .unknown:
                productsSubDirectory = "Debug"
                expectedProductName = "libFoo.a"
            }
            let products = try FileManager.default.contentsOfDirectory(atPath: fixturePath.appending(components: [".build", "out", "Products", productsSubDirectory]).pathString)
            #expect(products.contains(expectedProductName))
        }
    }
}
