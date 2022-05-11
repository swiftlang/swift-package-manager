//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import PackageLoading
import PackageModel
import SPMTestSupport
import TSCBasic
import XCTest

extension SystemLibraryTarget {
    convenience init(pkgConfig: String, providers: [SystemPackageProviderDescription] = []) {
        self.init(
            name: "Foo",
            path: AbsolutePath("/fake"),
            pkgConfig: pkgConfig.isEmpty ? nil : pkgConfig,
            providers: providers.isEmpty ? nil : providers)
    }
}

class PkgConfigTests: XCTestCase {
    let inputsDir = AbsolutePath(#file).parentDirectory.appending(components: "Inputs")

    func testBasics() throws {
        let fs = localFileSystem

        // No pkgConfig name.
        do {
            let observability = ObservabilitySystem.makeForTesting()
            let result = pkgConfigArgs(for: SystemLibraryTarget(pkgConfig: ""), fileSystem: fs, observabilityScope: observability.topScope)
            XCTAssertTrue(result.isEmpty)
        }

        // No pc file.
        do {
            let observability = ObservabilitySystem.makeForTesting()

            let target = SystemLibraryTarget(
                pkgConfig: "Foo",
                providers: [
                    .brew(["libFoo"]),
                    .apt(["libFoo-dev"]),
                    .yum(["libFoo-devel"]),
                    .nuget(["Foo"]),
                ]
            )
            for result in pkgConfigArgs(for: target, fileSystem: fs, observabilityScope: observability.topScope) {
                XCTAssertEqual(result.pkgConfigName, "Foo")
                XCTAssertEqual(result.cFlags, [])
                XCTAssertEqual(result.libs, [])
                switch result.provider {
                case .brew(let names)?:
                    XCTAssertEqual(names, ["libFoo"])
                case .apt(let names)?:
                    XCTAssertEqual(names, ["libFoo-dev"])
                case .yum(let names)?:
                    XCTAssertEqual(names, ["libFoo-devel"])
                case .nuget(let names)?:
                    XCTAssertEqual(names, ["Foo"])
                case nil:
                    XCTFail("Expected a provider here")
                }
                XCTAssertTrue(result.couldNotFindConfigFile)
                switch result.error {
                case PkgConfigError.couldNotFindConfigFile?: break
                default:
                    XCTFail("Unexpected error \(String(describing: result.error))")
                }
            }
        }

        // Pc file.
        try withCustomEnv(["PKG_CONFIG_PATH": inputsDir.pathString]) {
            let observability = ObservabilitySystem.makeForTesting()
            for result in pkgConfigArgs(for: SystemLibraryTarget(pkgConfig: "Foo"), fileSystem: fs, observabilityScope: observability.topScope) {
                XCTAssertEqual(result.pkgConfigName, "Foo")
                XCTAssertEqual(result.cFlags, ["-I/path/to/inc", "-I\(inputsDir.pathString)"])
                XCTAssertEqual(result.libs, ["-L/usr/da/lib", "-lSystemModule", "-lok"])
                XCTAssertNil(result.provider)
                XCTAssertNil(result.error)
                XCTAssertFalse(result.couldNotFindConfigFile)
            }
        }

        // Pc file with prohibited flags.
        try withCustomEnv(["PKG_CONFIG_PATH": inputsDir.pathString]) {
            let observability = ObservabilitySystem.makeForTesting()
            for result in pkgConfigArgs(for: SystemLibraryTarget(pkgConfig: "Bar"), fileSystem: fs, observabilityScope: observability.topScope) {
                XCTAssertEqual(result.pkgConfigName, "Bar")
                XCTAssertEqual(result.cFlags, ["-I/path/to/inc"])
                XCTAssertEqual(result.libs, ["-L/usr/da/lib", "-lSystemModule", "-lok"])
                XCTAssertNil(result.provider)
                XCTAssertFalse(result.couldNotFindConfigFile)
                switch result.error {
                case PkgConfigError.prohibitedFlags(let desc)?:
                    XCTAssertEqual(desc, "-DDenyListed")
                default:
                    XCTFail("unexpected error \(result.error.debugDescription)")
                }
            }
        }

        // Pc file with -framework Framework flag.
        try withCustomEnv(["PKG_CONFIG_PATH": inputsDir.pathString]) {
            let observability = ObservabilitySystem.makeForTesting()
            for result in pkgConfigArgs(for: SystemLibraryTarget(pkgConfig: "Framework"), fileSystem: fs, observabilityScope: observability.topScope) {
                XCTAssertEqual(result.pkgConfigName, "Framework")
                XCTAssertEqual(result.cFlags, ["-F/usr/lib"])
                XCTAssertEqual(result.libs, ["-F/usr/lib", "-framework", "SystemFramework"])
                XCTAssertNil(result.provider)
                XCTAssertFalse(result.couldNotFindConfigFile)
                switch result.error {
                case PkgConfigError.prohibitedFlags(let desc)?:
                    XCTAssertEqual(desc, "-DDenyListed")
                default:
                    XCTFail("unexpected error \(result.error.debugDescription)")
                }
            }
        }
    }

    func testDependencies() throws {
        // Use additionalSearchPaths instead of pkgConfigArgs to test handling
        // of search paths when loading dependencies.
        let observability = ObservabilitySystem.makeForTesting()
        let result = try PkgConfig(name: "Dependent", additionalSearchPaths: [inputsDir], fileSystem: localFileSystem, observabilityScope: observability.topScope)

        XCTAssertEqual(result.name, "Dependent")
        XCTAssertEqual(result.cFlags, ["-I/path/to/dependent/include", "-I/path/to/dependency/include"])
        XCTAssertEqual(result.libs, ["-L/path/to/dependent/lib", "-L/path/to/dependency/lib"])
    }
}
