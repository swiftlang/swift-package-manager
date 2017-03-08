/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Foundation

import Basic
import Commands
import PackageModel
import SourceControl
import TestSupport
import Utility
import Workspace
@testable import struct Workspace.PinsStore

final class PackageToolTests: XCTestCase {
    private func execute(_ args: [String], chdir: AbsolutePath? = nil) throws -> String {
        return try SwiftPMProduct.SwiftPackage.execute(args, chdir: chdir, printIfError: true)
    }

    func testUsage() throws {
        XCTAssert(try execute(["--help"]).contains("USAGE: swift package"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
    }

    func testFetch() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            // Check that `fetch` works.
            _ = try execute(["fetch"], chdir: packageRoot)
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])
        }
    }

    func testUpdate() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            // Perform an initial fetch.
            _ = try execute(["fetch"], chdir: packageRoot)
            var path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])

            // Retag the dependency, and update.
            let repo = GitRepository(path: prefix.appending(component: "Foo"))
            try repo.tag(name: "1.2.4")
            _ = try execute(["update"], chdir: packageRoot)

            // We shouldn't assume package path will be same after an update so ask again for it.
            path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3", "1.2.4"])
        }
    }

    func testDescribe() throws {
        fixture(name: "ClangModules/SwiftCMixed") { prefix in
            let output = try execute(["describe", "--type=json"], chdir: prefix)
            let json = try JSON(bytes: ByteString(encodingAsUTF8: output))

            XCTAssertEqual(json["name"]?.string, "SwiftCMixed")
            // Path should be an absolute path.
            XCTAssert(json["path"]?.string?.hasPrefix("/") == true)
            // Sort the module.
            let modules = json["modules"]?.array?.sorted {
                guard let first = $0["name"], let second = $1["name"] else {
                    return false
                }
                return first.stringValue < second.stringValue
            }

            XCTAssertEqual(modules?[0]["name"]?.stringValue, "CExec")
            XCTAssertEqual(modules?[2]["type"]?.stringValue, "library")
            XCTAssertEqual(modules?[1]["sources"]?.array?.map{$0.stringValue} ?? [], ["main.swift"])

            let textOutput = try execute(["describe"], chdir: prefix)
            
            XCTAssert(textOutput.hasPrefix("Name: SwiftCMixed"))
            XCTAssert(textOutput.contains("    C99name: CExec"))
            XCTAssert(textOutput.contains("    Name: SeaLib"))
            XCTAssert(textOutput.contains("   Sources: main.swift"))
        }
    }

    func testDumpPackage() throws {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let packageRoot = prefix.appending(component: "app")
            let dumpOutput = try execute(["dump-package"], chdir: packageRoot)
            let json = try JSON(bytes: ByteString(encodingAsUTF8: dumpOutput))
            guard case let .dictionary(contents) = json else { XCTFail("unexpected result"); return }
            guard case let .string(name)? = contents["name"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(name, "Dealer")
        }
    }

    func testShowDependencies() throws {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let packageRoot = prefix.appending(component: "app")
            let textOutput = try execute(["show-dependencies", "--format=text"], chdir: packageRoot)
            XCTAssert(textOutput.contains("FisherYates@1.2.3"))

            // FIXME: We have to fetch first otherwise the fetching output is mingled with the JSON data.
            let jsonOutput = try execute(["show-dependencies", "--format=json"], chdir: packageRoot)
            print("output = \(jsonOutput)")
            let json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))
            guard case let .dictionary(contents) = json else { XCTFail("unexpected result"); return }
            guard case let .string(name)? = contents["name"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(name, "Dealer")
            guard case let .string(path)? = contents["path"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(resolveSymlinks(AbsolutePath(path)), resolveSymlinks(packageRoot))
        }
    }

    func testInitEmpty() throws {
        mktmpdir { tmpPath in
            var fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["-C", path.asString, "init", "--type", "empty"])
            XCTAssert(fs.exists(path.appending(component: "Package.swift")))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources")), [])
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Tests")), [])
        }
    }

    func testInitExecutable() throws {
        mktmpdir { tmpPath in
            var fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["-C", path.asString, "init", "--type", "executable"])

            let manifest = path.appending(component: "Package.swift")
            let contents = try localFileSystem.readFileContents(manifest).asString!
            let version = "\(ToolsVersion.currentToolsVersion.major).\(ToolsVersion.currentToolsVersion.minor)"
            XCTAssertTrue(contents.hasPrefix("// swift-tools-version:\(version)\n"))

            XCTAssertTrue(fs.exists(manifest))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources")), ["main.swift"])
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Tests")), [])
        }
    }

    func testInitLibrary() throws {
        mktmpdir { tmpPath in
            var fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["-C", path.asString, "init"])
            XCTAssert(fs.exists(path.appending(component: "Package.swift")))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources")), ["Foo.swift"])
            XCTAssertEqual(
                try fs.getDirectoryContents(path.appending(component: "Tests")).sorted(),
                ["FooTests", "LinuxMain.swift"])
        }
    }

    func testPackageEditAndUnedit() {
        fixture(name: "Miscellaneous/PackageEdit") { prefix in
            let fooPath = prefix.appending(component: "foo")
            func build() throws -> String {
                return try SwiftPMProduct.SwiftBuild.execute([], chdir: fooPath, printIfError: true)
            }

            // Put bar and baz in edit mode.
            _ = try SwiftPMProduct.SwiftPackage.execute(["edit", "bar", "--branch", "bugfix"], chdir: fooPath, printIfError: true)
            _ = try SwiftPMProduct.SwiftPackage.execute(["edit", "baz", "--branch", "bugfix"], chdir: fooPath, printIfError: true)

            // Path to the executable.
            let exec = [fooPath.appending(components: ".build", "debug", "foo").asString]

            // We should see it now in packages directory.
            let editsPath = fooPath.appending(components: "Packages", "bar")
            XCTAssert(isDirectory(editsPath))

            let bazEditsPath = fooPath.appending(components: "Packages", "baz")
            XCTAssert(isDirectory(bazEditsPath))
            // Removing baz externally should just emit an warning and not a build failure.
            try removeFileTree(bazEditsPath)

            // Do a modification in bar and build.
            try localFileSystem.writeFileContents(editsPath.appending(components: "Sources", "bar.swift"), bytes: "public let theValue = 88888\n")
            let buildOutput = try build()

            XCTAssert(buildOutput.contains("baz was being edited but has been removed, falling back to original checkout."))
            // We should be able to see that modification now.
            XCTAssertEqual(try Process.checkNonZeroExit(arguments: exec), "88888\n")
            // The branch of edited package should be the one we provided when putting it in edit mode.
            let editsRepo = GitRepository(path: editsPath)
            XCTAssertEqual(try editsRepo.currentBranch(), "bugfix")

            // It shouldn't be possible to unedit right now because of uncommited changes.
            do {
                _ = try SwiftPMProduct.SwiftPackage.execute(["unedit", "bar"], chdir: fooPath)
                XCTFail("Unexpected unedit success")
            } catch {}

            try editsRepo.stageEverything()
            try editsRepo.commit()

            // It shouldn't be possible to unedit right now because of unpushed changes.
            do {
                _ = try SwiftPMProduct.SwiftPackage.execute(["unedit", "bar"], chdir: fooPath)
                XCTFail("Unexpected unedit success")
            } catch {}

            // Push the changes.
            try editsRepo.push(remote: "origin", branch: "bugfix")

            // We should be able to unedit now.
            _ = try SwiftPMProduct.SwiftPackage.execute(["unedit", "bar"], chdir: fooPath, printIfError: true)

            // Test editing with a path i.e. ToT development.
            let bazTot = prefix.appending(component: "tot")
            try SwiftPMProduct.SwiftPackage.execute(["edit", "baz", "--path", bazTot.asString], chdir: fooPath, printIfError: true)
            XCTAssertTrue(exists(bazTot))
            XCTAssertTrue(isSymlink(bazEditsPath))

            // Edit a file in baz ToT checkout.
            let bazTotPackageFile = bazTot.appending(component: "Package.swift")
            let stream = BufferedOutputByteStream()
            stream <<< (try localFileSystem.readFileContents(bazTotPackageFile)) <<< "\n// Edited."
            try localFileSystem.writeFileContents(bazTotPackageFile, bytes: stream.bytes)

            // Unediting baz will remove the symlink but not the checked out package.
            try SwiftPMProduct.SwiftPackage.execute(["unedit", "baz"], chdir: fooPath, printIfError: true)
            XCTAssertTrue(exists(bazTot))
            XCTAssertFalse(isSymlink(bazEditsPath))

            // Check that on re-editing with path, we don't make a new clone.
            try SwiftPMProduct.SwiftPackage.execute(["edit", "baz", "--path", bazTot.asString], chdir: fooPath, printIfError: true)
            XCTAssertTrue(isSymlink(bazEditsPath))
            XCTAssertEqual(try localFileSystem.readFileContents(bazTotPackageFile), stream.bytes)
        }
    }

    func testPackageClean() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            // Build it.
            XCTAssertBuilds(packageRoot)
            XCTAssertFileExists(packageRoot.appending(components: ".build", "debug", "Bar"))
            XCTAssert(isDirectory(packageRoot.appending(component: ".build")))

            // Clean, and check for removal of the build directory but not Packages.
            _ = try execute(["clean"], chdir: packageRoot)
            XCTAssert(!exists(packageRoot.appending(components: ".build", "debug", "Bar")))
            // Clean again to ensure we get no error.
            _ = try execute(["clean"], chdir: packageRoot)
        }
    }

    func testPackageReset() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            // Build it.
            XCTAssertBuilds(packageRoot)
            XCTAssertFileExists(packageRoot.appending(components: ".build", "debug", "Bar"))
            XCTAssert(isDirectory(packageRoot.appending(component: ".build")))
            // Clean, and check for removal of the build directory but not Packages.

            _ = try execute(["clean"], chdir: packageRoot)
            XCTAssert(!exists(packageRoot.appending(components: ".build", "debug", "Bar")))
            XCTAssertFalse(try localFileSystem.getDirectoryContents(packageRoot.appending(components: ".build", "repositories")).isEmpty)

            // Fully clean.
            _ = try execute(["reset"], chdir: packageRoot)
            XCTAssertTrue(try localFileSystem.getDirectoryContents(packageRoot.appending(components: ".build", "repositories")).isEmpty)
            // We preserve cache directories.
            XCTAssert(isDirectory(packageRoot.appending(component: ".build")))
        }
    }

    func testPinning() throws {
        fixture(name: "Miscellaneous/PackageEdit") { prefix in
            let fooPath = prefix.appending(component: "foo")
            func build() throws -> String {
                let buildOutput = try SwiftPMProduct.SwiftBuild.execute([], chdir: fooPath, printIfError: true)
                return buildOutput
            }
            let exec = [fooPath.appending(components: ".build", "debug", "foo").asString]

            // Build and sanity check.
            _ = try build()
            XCTAssertEqual(try Process.checkNonZeroExit(arguments: exec).chomp(), "\(5)")

            // Get path to bar checkout.
            let barPath = try SwiftPMProduct.packagePath(for: "bar", packageRoot: fooPath)

            // Checks the content of checked out bar.swift.
            func checkBar(_ value: Int, file: StaticString = #file, line: UInt = #line) throws {
                let contents = try localFileSystem.readFileContents(barPath.appending(components:"Sources", "bar.swift")).asString?.chomp()
                XCTAssert(contents?.hasSuffix("\(value)") ?? false, file: file, line: line)
            }

            // We should see a pin file now.
            let pinsFile = fooPath.appending(component: "Package.pins")
            XCTAssert(exists(pinsFile))

            // Test pins file.
            do {
                let pinsStore = PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                XCTAssert(!pinsStore.hasError)
                XCTAssert(pinsStore.autoPin)
                XCTAssertEqual(pinsStore.pins.map{$0}.count, 2)
                for pkg in ["bar", "baz"] {
                    let pin = pinsStore.pinsMap[pkg]!
                    XCTAssertEqual(pin.package, pkg)
                    XCTAssert(pin.repository.url.hasSuffix(pkg))
                    XCTAssertEqual(pin.state.version, "1.2.3")
                    XCTAssertEqual(pin.reason, nil)
                }
            }

            @discardableResult
            func execute(_ args: String..., printError: Bool = true) throws -> String {
                return try SwiftPMProduct.SwiftPackage.execute([] + args, chdir: fooPath, printIfError: printError)
            }
            
            // Enable autopin.
            do {
                try execute("pin", "--enable-autopin")
                let pinsStore = PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                XCTAssert(!pinsStore.hasError)
                XCTAssert(pinsStore.autoPin)
            }

            // Disable autopin.
            do {
                try execute("pin", "--disable-autopin")
                let pinsStore = PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                XCTAssert(!pinsStore.hasError)
                XCTAssertFalse(pinsStore.autoPin)
            }

            // Try to pin bar.
            do {
                try execute("pin", "bar")
                let pinsStore = PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                XCTAssert(!pinsStore.hasError)
                XCTAssertEqual(pinsStore.pinsMap["bar"]!.state.version, "1.2.3")
            }

            // Update bar repo.
            do {
                let barPath = prefix.appending(component: "bar")
                let barRepo = GitRepository(path: barPath)
                try localFileSystem.writeFileContents(barPath.appending(components: "Sources", "bar.swift"), bytes: "public let theValue = 6\n")
                try barRepo.stageEverything()
                try barRepo.commit()
                try barRepo.tag(name: "1.2.4")
            }

            // Run package update and ensure that it is not updated due to pinning.
            do {
                try execute("update")
                try checkBar(5)
            }

            // Running package update with --repin should update the package.
            do {
                try execute("update", "--repin")
                try checkBar(6)
            }

            // We should be able to revert to a older version.
            do {
                try execute("pin", "bar", "--version", "1.2.3", "--message", "bad deppy")
                let pinsStore = PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                XCTAssert(!pinsStore.hasError)
                XCTAssertEqual(pinsStore.pinsMap["bar"]!.reason, "bad deppy")
                XCTAssertEqual(pinsStore.pinsMap["bar"]!.state.version, "1.2.3")
                try checkBar(5)
            }

            // Unpinning bar and updating should get the latest version.
            do {
                try execute("unpin", "bar")
                try execute("update")
                let pinsStore = PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                XCTAssertEqual(pinsStore.pinsMap["bar"], nil)
                XCTAssert(!pinsStore.hasError)
                try checkBar(6)
            }

            // Try pinning a dependency which is in edit mode.
            do {
                try execute("edit", "bar", "--branch", "bugfix")
                do {
                    try execute("pin", "bar", printError: false)
                    XCTFail("This should have been an error")
                } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                    XCTAssertEqual(stderr, "error: The provided package is in editable state\n")
                }
                try execute("unedit", "bar")
            }

            // Try pinning all the dependencies.
            do {
                try execute("pin", "--all")
                let pinsStore = PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                XCTAssert(!pinsStore.hasError)
                XCTAssertEqual(pinsStore.pinsMap["bar"]!.state.version, "1.2.4")
                XCTAssertEqual(pinsStore.pinsMap["baz"]!.state.version, "1.2.3")
            }
        }
    }

    static var allTests = [
        ("testDescribe", testDescribe),
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testFetch", testFetch),
        ("testUpdate", testUpdate),
        ("testDumpPackage", testDumpPackage),
        ("testShowDependencies", testShowDependencies),
        ("testInitEmpty", testInitEmpty),
        ("testInitExecutable", testInitExecutable),
        ("testInitLibrary", testInitLibrary),
        ("testPackageClean", testPackageClean),
        ("testPackageEditAndUnedit", testPackageEditAndUnedit),
        ("testPackageReset", testPackageReset),
        ("testPinning", testPinning),
    ]
}
