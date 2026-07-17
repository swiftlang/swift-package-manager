//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Basics
import PackageLoading
import PackageModel
import _InternalTestSupport
import Testing

/// These tests verify that executable products can be backed by single binary targets
@Suite(
    .tags(
        .TestSize.medium
    )
)
struct BinaryTargetExecutableTests {

    /// Test that an executable product can be backed by a single binary target
    /// This validates the changes in PackageBuilder.validateExecutableProduct
    @Test
    func testExecutableProductWithSingleBinaryTarget() throws {
        let fs = InMemoryFileSystem()
        try fs.writeFileContents("/foo.zip", bytes: "")

        let manifest = Manifest.createRootManifest(
            displayName: "MyPackage",
            products: [
                try ProductDescription(name: "MyExecutable", type: .executable, targets: ["MyBinary"]),
            ],
            targets: [
                try TargetDescription(name: "MyBinary", path: "./foo.zip", type: .binary),
            ]
        )

        let binaryArtifacts = [
            "MyBinary": BinaryArtifact(kind: .artifactsArchive(types: [.executable]), originURL: nil, path: "/foo.artifactbundle"),
        ]

        try PackageBuilderTester(manifest, binaryArtifacts: binaryArtifacts, in: fs) { package, diagnostics in
            // Should not produce any diagnostics - this should work
            diagnostics.checkIsEmpty()

            try package.checkModule("MyBinary") { module in
                module.check(type: .binary)
            }

            package.checkProduct("MyExecutable") { product in
                product.check(type: .executable, targets: ["MyBinary"])
            }
        }
    }

    /// Test that an executable product with multiple targets that include a binary target fails
    /// This ensures we maintain existing validation for products with multiple targets
    @Test
    func testExecutableProductWithMultipleTargetsIncludingBinary() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/SwiftTarget/main.swift"
        )
        try fs.writeFileContents("/binary.zip", bytes: "")

        let manifest = Manifest.createRootManifest(
            displayName: "MyPackage",
            products: [
                try ProductDescription(name: "MyExecutable", type: .executable, targets: ["SwiftTarget", "BinaryTarget"]),
            ],
            targets: [
                try TargetDescription(name: "SwiftTarget"),
                try TargetDescription(name: "BinaryTarget", path: "./binary.zip", type: .binary),
            ]
        )

        let binaryArtifacts = [
            "BinaryTarget": BinaryArtifact(kind: .artifactsArchive(types: [.executable]), originURL: nil, path: "/binary.artifactbundle"),
        ]

        try PackageBuilderTester(manifest, binaryArtifacts: binaryArtifacts, in: fs) { package, diagnostics in
            // Should still fail because we have multiple targets
            diagnostics.check(
                diagnostic: "executable product 'MyExecutable' should not have more than one executable target",
                severity: .error
            )

            // Check all modules even when there are errors
            try package.checkModule("SwiftTarget") { _ in }
            try package.checkModule("BinaryTarget") { _ in }
        }
    }

    /// Test that regular executable products still work as before
    /// This is a regression test to ensure existing behavior is preserved
    @Test
    func testRegularExecutableProductStillWorks() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/MyExecutable/main.swift"
        )

        let manifest = Manifest.createRootManifest(
            displayName: "MyPackage",
            products: [
                try ProductDescription(name: "MyExecutable", type: .executable, targets: ["MyExecutable"]),
            ],
            targets: [
                try TargetDescription(name: "MyExecutable"),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            // Should work as before
            diagnostics.checkIsEmpty()

            try package.checkModule("MyExecutable") { module in
                module.check(type: .executable)
            }

            package.checkProduct("MyExecutable") { product in
                product.check(type: .executable, targets: ["MyExecutable"])
            }
        }
    }

    /// Test that executable products with multiple executable targets still fail
    /// This ensures we maintain existing validation
    @Test
    func testExecutableProductWithMultipleExecutableTargetsFails() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Exec1/main.swift",
            "/Sources/Exec2/main.swift"
        )

        let manifest = Manifest.createRootManifest(
            displayName: "MyPackage",
            products: [
                try ProductDescription(name: "MyExecutable", type: .executable, targets: ["Exec1", "Exec2"]),
            ],
            targets: [
                try TargetDescription(name: "Exec1"),
                try TargetDescription(name: "Exec2"),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            // Should fail as before
            diagnostics.check(
                diagnostic: "executable product 'MyExecutable' should not have more than one executable target",
                severity: .error
            )

            // Check all modules even when there are errors
            try package.checkModule("Exec1") { _ in }
            try package.checkModule("Exec2") { _ in }
        }
    }

    /// Test that binary target executable dependency checking works
    /// This validates that depending on a binary target doesn't emit errors when the target type is binary
    @Test
    func testBinaryTargetDependencyValidation() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/RegularTarget/lib.swift"
        )
        try fs.writeFileContents("/binary.zip", bytes: "")

        let manifest = Manifest.createRootManifest(
            displayName: "MyPackage",
            products: [
                try ProductDescription(name: "RegularLibrary", type: .library(.automatic), targets: ["RegularTarget"]),
                try ProductDescription(name: "BinaryExecutable", type: .executable, targets: ["BinaryTarget"]),
            ],
            targets: [
                try TargetDescription(name: "RegularTarget", dependencies: ["BinaryTarget"]),
                try TargetDescription(name: "BinaryTarget", path: "./binary.zip", type: .binary),
            ]
        )

        let binaryArtifacts = [
            "BinaryTarget": BinaryArtifact(kind: .artifactsArchive(types: [.executable]), originURL: nil, path: "/binary.artifactbundle"),
        ]

        try PackageBuilderTester(manifest, binaryArtifacts: binaryArtifacts, in: fs) { package, diagnostics in
            // Should not emit errors for depending on binary targets
            diagnostics.checkIsEmpty()

            try package.checkModule("BinaryTarget") { module in
                module.check(type: .binary)
            }

            try package.checkModule("RegularTarget") { module in
                module.check(type: .library)
                module.check(targetDependencies: ["BinaryTarget"])
            }

            package.checkProduct("BinaryExecutable") { product in
                product.check(type: .executable, targets: ["BinaryTarget"])
            }

            package.checkProduct("RegularLibrary") { product in
                product.check(type: .library(.automatic), targets: ["RegularTarget"])
            }
        }
    }

    /// Test edge case: executable product with zero executable targets but one binary target
    /// This validates the specific logic change that allows binary targets
    @Test
    func testExecutableProductWithZeroExecutableTargetsButOneBinary() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/LibraryTarget/lib.swift"
        )
        try fs.writeFileContents("/binary.zip", bytes: "")

        let manifest = Manifest.createRootManifest(
            displayName: "MyPackage",
            products: [
                // This would previously fail because LibraryTarget is not executable
                // and BinaryTarget would be checked as non-executable
                // But now it should pass because we have exactly one binary target
                try ProductDescription(name: "MyProduct", type: .executable, targets: ["BinaryTarget"]),
            ],
            targets: [
                try TargetDescription(name: "LibraryTarget"),
                try TargetDescription(name: "BinaryTarget", path: "./binary.zip", type: .binary),
            ]
        )

        let binaryArtifacts = [
            "BinaryTarget": BinaryArtifact(kind: .artifactsArchive(types: [.executable]), originURL: nil, path: "/binary.artifactbundle"),
        ]

        try PackageBuilderTester(manifest, binaryArtifacts: binaryArtifacts, in: fs) { package, diagnostics in
            // This should now work with the changes
            diagnostics.checkIsEmpty()

            try package.checkModule("LibraryTarget") { module in
                module.check(type: .library)
            }

            try package.checkModule("BinaryTarget") { module in
                module.check(type: .binary)
            }

            package.checkProduct("MyProduct") { product in
                product.check(type: .executable, targets: ["BinaryTarget"])
            }
        }
    }

    /// Test compatibility with XCFramework binary targets
    /// Ensures the changes work with different binary artifact types
    @Test
    func testExecutableProductWithXCFrameworkBinaryTarget() throws {
        let fs = InMemoryFileSystem()
        try fs.writeFileContents("/framework.zip", bytes: "")

        let manifest = Manifest.createRootManifest(
            displayName: "MyPackage",
            products: [
                try ProductDescription(name: "FrameworkExecutable", type: .executable, targets: ["FrameworkTarget"]),
            ],
            targets: [
                try TargetDescription(name: "FrameworkTarget", path: "./framework.zip", type: .binary),
            ]
        )

        let binaryArtifacts = [
            "FrameworkTarget": BinaryArtifact(kind: .xcframework, originURL: nil, path: "/framework.xcframework"),
        ]

        try PackageBuilderTester(manifest, binaryArtifacts: binaryArtifacts, in: fs) { package, diagnostics in
            // Should work even with XCFramework
            diagnostics.checkIsEmpty()

            try package.checkModule("FrameworkTarget") { module in
                module.check(type: .binary)
            }

            package.checkProduct("FrameworkExecutable") { product in
                product.check(type: .executable, targets: ["FrameworkTarget"])
            }
        }
    }
}
