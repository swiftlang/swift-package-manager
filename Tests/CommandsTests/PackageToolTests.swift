/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TestSupport
import Basic
import Commands
import SourceControl
import func POSIX.popen
import class Utility.Git

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
            XCTAssert(fs.exists(path.appending(component: "Package.swift")))
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
                return try SwiftPMProduct.SwiftBuild.execute(["--enable-new-resolver"], chdir: fooPath, printIfError: true)
            }
            // Build the package.
            _ = try build()

            let exec = [fooPath.appending(components: ".build", "debug", "foo").asString]
            // Sanity check.
            XCTAssertEqual(try popen(exec), "5\n")

            // Put bar and baz in edit mode.
            _ = try SwiftPMProduct.SwiftPackage.execute(["edit", "--name", "bar", "--branch", "bugfix", "--enable-new-resolver"], chdir: fooPath, printIfError: true)
            _ = try SwiftPMProduct.SwiftPackage.execute(["edit", "--name", "baz", "--branch", "bugfix", "--enable-new-resolver"], chdir: fooPath, printIfError: true)

            // We should see it now in packages directory.
            let editsPath = fooPath.appending(components: "Packages", "bar")
            XCTAssert(isDirectory(editsPath))

            let bazEditsPath = fooPath.appending(components: "Packages", "baz")
            XCTAssert(isDirectory(bazEditsPath))
            // Removing baz externally should just emit an warning and not a build failure.
            try removeFileTree(bazEditsPath)

            // Do a modification in bar and build.
            try localFileSystem.writeFileContents(editsPath.appending(components: "Sources", "bar.swift"), bytes: "public let theValue = 8\n")
            let buildOutput = try build()

            XCTAssert(buildOutput.contains("baz was being edited but has been removed, falling back to original checkout."))
            // We should be able to see that modification now.
            XCTAssertEqual(try popen(exec), "8\n")
            // The branch of edited package should be the one we provided when putting it in edit mode.
            let editsRepo = GitRepository(path: editsPath)
            XCTAssertEqual(try editsRepo.currentBranch(), "bugfix")

            // It shouldn't be possible to unedit right now because of uncommited changes.
            do {
                _ = try SwiftPMProduct.SwiftPackage.execute(["unedit", "--name", "bar", "--enable-new-resolver"], chdir: fooPath)
                XCTFail("Unexpected unedit success")
            } catch {}

            try editsRepo.stageEverything()
            try editsRepo.commit()

            // It shouldn't be possible to unedit right now because of unpushed changes.
            do {
                _ = try SwiftPMProduct.SwiftPackage.execute(["unedit", "--name", "bar", "--enable-new-resolver"], chdir: fooPath)
                XCTFail("Unexpected unedit success")
            } catch {}

            // Push the changes.
            try editsRepo.push(remote: "origin", branch: "bugfix")

            // We should be able to unedit now.
            _ = try SwiftPMProduct.SwiftPackage.execute(["unedit", "--name", "bar", "--enable-new-resolver"], chdir: fooPath, printIfError: true)
        }
    }

    func testPackageReset() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            // Build it.
            XCTAssertBuilds(packageRoot)
            XCTAssertFileExists(packageRoot.appending(components: ".build", "debug", "Bar"))
            XCTAssert(isDirectory(packageRoot.appending(component: ".build")))
            // FIXME: Eliminate this.
            if !SwiftPMProduct.enableNewResolver {
                XCTAssert(isDirectory(packageRoot.appending(component: "Packages")))
            }

            // Clean, and check for removal of the build directory but not Packages.

            _ = try SwiftPMProduct.SwiftBuild.execute(["--clean"], chdir: packageRoot, printIfError: true)
            XCTAssert(!exists(packageRoot.appending(components: ".build", "debug", "Bar")))
            // We don't delete the build folder in new resolver.
            // FIXME: Eliminate this once we switch to new resolver.
            if !SwiftPMProduct.enableNewResolver {
                XCTAssert(!isDirectory(packageRoot.appending(component: ".build")))
                XCTAssert(isDirectory(packageRoot.appending(component: "Packages")))
            }

            // Fully clean, and check for removal of both.
            _ = try execute(["reset"], chdir: packageRoot)
            XCTAssert(!isDirectory(packageRoot.appending(component: ".build")))
            // FIXME: Eliminate this.
            if !SwiftPMProduct.enableNewResolver {
                XCTAssert(!isDirectory(packageRoot.appending(component: "Packages")))
            }
        }
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testFetch", testFetch),
        ("testUpdate", testUpdate),
        ("testDumpPackage", testDumpPackage),
        ("testShowDependencies", testShowDependencies),
        ("testInitEmpty", testInitEmpty),
        ("testInitExecutable", testInitExecutable),
        ("testInitLibrary", testInitLibrary),
        ("testPackageEditAndUnedit", testPackageEditAndUnedit),
        ("testPackageReset", testPackageReset),
    ]
}
