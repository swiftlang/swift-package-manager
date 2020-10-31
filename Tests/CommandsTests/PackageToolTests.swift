/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Foundation

import TSCBasic
import Commands
import Xcodeproj
import PackageModel
import SourceControl
import SPMTestSupport
import TSCUtility
import Workspace

final class PackageToolTests: XCTestCase {
    @discardableResult
    private func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        env: [String: String]? = nil
    ) throws -> (stdout: String, stderr: String) {
        return try SwiftPMProduct.SwiftPackage.execute(args, packagePath: packagePath, env: env)
    }

    func testUsage() throws {
        XCTAssert(try execute(["--help"]).stdout.contains("USAGE: swift package"))
    }

    func testSeeAlso() throws {
        XCTAssert(try execute(["--help"]).stdout.contains("SEE ALSO: swift build, swift run, swift test"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).stdout.contains("Swift Package Manager"))
    }
    
    func testNetrcFile() throws {
        func verifyUnsupportedOSThrows() {
            do {
                // should throw and be caught
                try execute(["update", "--netrc-file", "/Users/me/.hidden/.netrc"])
                XCTFail()
            } catch {
                XCTAssert(true)
            }
        }
        #if os(macOS)
        if #available(macOS 10.13, *) {
            // should succeed
            XCTAssert(try execute(["--netrc-file", "/Users/me/.hidden/.netrc"]).stdout.contains("USAGE: swift package"))
        } else {
            verifyUnsupportedOSThrows()
        }
        #else
            verifyUnsupportedOSThrows()
        #endif
    }

    func testResolve() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            // Check that `resolve` works.
            _ = try execute(["resolve"], packagePath: packageRoot)
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])
        }
    }

    func testUpdate() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            // Perform an initial fetch.
            _ = try execute(["resolve"], packagePath: packageRoot)
            var path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])

            // Retag the dependency, and update.
            let repo = GitRepository(path: prefix.appending(component: "Foo"))
            try repo.tag(name: "1.2.4")
            _ = try execute(["update"], packagePath: packageRoot)

            // We shouldn't assume package path will be same after an update so ask again for it.
            path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3", "1.2.4"])
        }
    }

    func testDescribe() throws {
        fixture(name: "CFamilyTargets/SwiftCMixed") { prefix in
            let result = try SwiftPMProduct.SwiftPackage.executeProcess(["describe", "--type=json"], packagePath: prefix)
            let output = try result.utf8Output()
            let json = try JSON(bytes: ByteString(encodingAsUTF8: output))

            XCTAssertEqual(json["name"]?.string, "SwiftCMixed")
            // Path should be an absolute path.
            XCTAssert(json["path"]?.string?.hasPrefix("/") == true)
            // Sort the target.
            let targets = json["targets"]?.array?.sorted {
                guard let first = $0["name"], let second = $1["name"] else {
                    return false
                }
                return first.stringValue < second.stringValue
            }

            XCTAssertEqual(targets?[0]["name"]?.stringValue, "CExec")
            XCTAssertEqual(targets?[2]["type"]?.stringValue, "library")
            XCTAssertEqual(targets?[1]["sources"]?.array?.map{$0.stringValue} ?? [], ["main.swift"])

            let (textOutput, _) = try execute(["describe"], packagePath: prefix)

            XCTAssert(textOutput.hasPrefix("Name: SwiftCMixed"))
            XCTAssert(textOutput.contains("    C99name: CExec"))
            XCTAssert(textOutput.contains("    Name: SeaLib"))
            XCTAssert(textOutput.contains("   Sources: main.swift"))
        }
    }

    func testDumpPackage() throws {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let packageRoot = prefix.appending(component: "app")
            let (dumpOutput, _) = try execute(["dump-package"], packagePath: packageRoot)
            let json = try JSON(bytes: ByteString(encodingAsUTF8: dumpOutput))
            guard case let .dictionary(contents) = json else { XCTFail("unexpected result"); return }
            guard case let .string(name)? = contents["name"] else { XCTFail("unexpected result"); return }
            guard case let .array(platforms)? = contents["platforms"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(name, "Dealer")
            XCTAssertEqual(platforms, [
                .dictionary([
                    "platformName": .string("macos"),
                    "version": .string("10.12"),
                    "options": .array([])
                ]),
                .dictionary([
                    "platformName": .string("ios"),
                    "version": .string("10.0"),
                    "options": .array([])
                ]),
                .dictionary([
                    "platformName": .string("tvos"),
                    "version": .string("11.0"),
                    "options": .array([])
                ]),
                .dictionary([
                    "platformName": .string("watchos"),
                    "version": .string("5.0"),
                    "options": .array([])
                ]),
            ])
        }
    }

    func testShowDependencies() throws {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let packageRoot = prefix.appending(component: "app")
            let textOutput = try SwiftPMProduct.SwiftPackage.executeProcess(["show-dependencies", "--format=text"], packagePath: packageRoot).utf8Output()
            XCTAssert(textOutput.contains("FisherYates@1.2.3"))

            let jsonOutput = try SwiftPMProduct.SwiftPackage.executeProcess(["show-dependencies", "--format=json"], packagePath: packageRoot).utf8Output()
            let json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))
            guard case let .dictionary(contents) = json else { XCTFail("unexpected result"); return }
            guard case let .string(name)? = contents["name"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(name, "Dealer")
            guard case let .string(path)? = contents["path"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(resolveSymlinks(AbsolutePath(path)), resolveSymlinks(packageRoot))
        }
    }

    func testShowDependencies_dotFormat_sr12016() {
        // Confirm that SR-12016 is resolved.
        // See https://bugs.swift.org/browse/SR-12016
        
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/PackageA/Sources/TargetA/main.swift",
            "/PackageB/Sources/TargetB/B.swift",
            "/PackageC/Sources/TargetC/C.swift",
            "/PackageD/Sources/TargetD/D.swift",
        ])
        
        let manifestA = Manifest.createManifest(
            name: "PackageA",
            path: "/PackageA",
            url: "/PackageA",
            v: .currentToolsVersion,
            packageKind: .root,
            dependencies: [
                .init(name: "PackageB", url: "/PackageB", requirement: .localPackage),
                .init(name: "PackageC", url: "/PackageC", requirement: .localPackage),
            ],
            products: [
                .init(name: "exe", type: .executable, targets: ["TargetA"])
            ],
            targets: [
                .init(name: "TargetA", dependencies: ["PackageB", "PackageC"])
            ]
        )
        
        let manifestB = Manifest.createManifest(
            name: "PackageB",
            path: "/PackageB",
            url: "/PackageB",
            v: .currentToolsVersion,
            packageKind: .local,
            dependencies: [
                .init(name: "PackageC", url: "/PackageC", requirement: .localPackage),
                .init(name: "PackageD", url: "/PackageD", requirement: .localPackage),
            ],
            products: [
                .init(name: "PackageB", type: .library(.dynamic), targets: ["TargetB"])
            ],
            targets: [
                .init(name: "TargetB", dependencies: ["PackageC", "PackageD"])
            ]
        )
        
        let manifestC = Manifest.createManifest(
            name: "PackageC",
            path: "/PackageC",
            url: "/PackageC",
            v: .currentToolsVersion,
            packageKind: .local,
            dependencies: [
                .init(name: "PackageD", url: "/PackageD", requirement: .localPackage),
            ],
            products: [
                .init(name: "PackageC", type: .library(.dynamic), targets: ["TargetC"])
            ],
            targets: [
                .init(name: "TargetC", dependencies: ["PackageD"])
            ]
        )
        
        let manifestD = Manifest.createManifest(
            name: "PackageD",
            path: "/PackageD",
            url: "/PackageD",
            v: .currentToolsVersion,
            packageKind: .local,
            products: [
                .init(name: "PackageD", type: .library(.dynamic), targets: ["TargetD"])
            ],
            targets: [
                .init(name: "TargetD")
            ]
        )
        
        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(fs: fileSystem, diagnostics: diagnostics,
                                     manifests: [manifestA, manifestB, manifestC, manifestD])
        XCTAssertNoDiagnostics(diagnostics)
        
        let output = BufferedOutputByteStream()
        dumpDependenciesOf(rootPackage: graph.rootPackages[0], mode: .dot, on: output)
        let dotFormat = output.bytes.description
        
        var alreadyPutOut: Set<Substring> = []
        for line in dotFormat.split(whereSeparator: { $0.isNewline }) {
            if alreadyPutOut.contains(line) {
                XCTFail("Same line was already put out: \(line)")
            }
            alreadyPutOut.insert(line)
        }
        
        let expectedLines: [Substring] = [
            #""/PackageA" [label="PackageA\n/PackageA\nunspecified"]"#,
            #""/PackageB" [label="PackageB\n/PackageB\nunspecified"]"#,
            #""/PackageC" [label="PackageC\n/PackageC\nunspecified"]"#,
            #""/PackageD" [label="PackageD\n/PackageD\nunspecified"]"#,
            #""/PackageA" -> "/PackageB""#,
            #""/PackageA" -> "/PackageC""#,
            #""/PackageB" -> "/PackageC""#,
            #""/PackageB" -> "/PackageD""#,
            #""/PackageC" -> "/PackageD""#,
        ]
        for expectedLine in expectedLines {
            XCTAssertTrue(alreadyPutOut.contains(expectedLine),
                          "Expected line is not found: \(expectedLine)")
        }
    }

    func testInitEmpty() throws {
        mktmpdir { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["init", "--type", "empty"], packagePath: path)

            XCTAssert(fs.exists(path.appending(component: "Package.swift")))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources")), [])
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Tests")), [])
        }
    }

    func testInitExecutable() throws {
        mktmpdir { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["init", "--type", "executable"], packagePath: path)

            let manifest = path.appending(component: "Package.swift")
            let contents = try localFileSystem.readFileContents(manifest).description
            let version = "\(InitPackage.newPackageToolsVersion.major).\(InitPackage.newPackageToolsVersion.minor)"
            XCTAssertTrue(contents.hasPrefix("// swift-tools-version:\(version)\n"))

            XCTAssertTrue(fs.exists(manifest))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources").appending(component: "Foo")), ["main.swift"])
            XCTAssertEqual(
                try fs.getDirectoryContents(path.appending(component: "Tests")).sorted(),
                ["FooTests", "LinuxMain.swift"])
        }
    }

    func testInitLibrary() throws {
        mktmpdir { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["init"], packagePath: path)

            XCTAssert(fs.exists(path.appending(component: "Package.swift")))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources").appending(component: "Foo")), ["Foo.swift"])
            XCTAssertEqual(
                try fs.getDirectoryContents(path.appending(component: "Tests")).sorted(),
                ["FooTests", "LinuxMain.swift"])
        }
    }

    func testInitCustomNameExecutable() throws {
        mktmpdir { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["init", "--name", "CustomName", "--type", "executable"], packagePath: path)

            let manifest = path.appending(component: "Package.swift")
            let contents = try localFileSystem.readFileContents(manifest).description
            let version = "\(InitPackage.newPackageToolsVersion.major).\(InitPackage.newPackageToolsVersion.minor)"
            XCTAssertTrue(contents.hasPrefix("// swift-tools-version:\(version)\n"))

            XCTAssertTrue(fs.exists(manifest))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources").appending(component: "CustomName")), ["main.swift"])
            XCTAssertEqual(
                try fs.getDirectoryContents(path.appending(component: "Tests")).sorted(),
                ["CustomNameTests", "LinuxMain.swift"])
        }
    }

    func testPackageEditAndUnedit() {
        fixture(name: "Miscellaneous/PackageEdit") { prefix in
            let fooPath = prefix.appending(component: "foo")
            func build() throws -> (stdout: String, stderr: String) {
                return try SwiftPMProduct.SwiftBuild.execute([], packagePath: fooPath)
            }

            // Put bar and baz in edit mode.
            _ = try SwiftPMProduct.SwiftPackage.execute(["edit", "bar", "--branch", "bugfix"], packagePath: fooPath)
            _ = try SwiftPMProduct.SwiftPackage.execute(["edit", "baz", "--branch", "bugfix"], packagePath: fooPath)

            // Path to the executable.
            let exec = [fooPath.appending(components: ".build", Resources.default.toolchain.triple.tripleString, "debug", "foo").pathString]

            // We should see it now in packages directory.
            let editsPath = fooPath.appending(components: "Packages", "bar")
            XCTAssert(localFileSystem.isDirectory(editsPath))

            let bazEditsPath = fooPath.appending(components: "Packages", "baz")
            XCTAssert(localFileSystem.isDirectory(bazEditsPath))
            // Removing baz externally should just emit an warning and not a build failure.
            try localFileSystem.removeFileTree(bazEditsPath)

            // Do a modification in bar and build.
            try localFileSystem.writeFileContents(editsPath.appending(components: "Sources", "bar.swift"), bytes: "public let theValue = 88888\n")
            let (_, stderr) = try build()

            XCTAssertMatch(stderr, .contains("dependency 'baz' was being edited but is missing; falling back to original checkout"))
            // We should be able to see that modification now.
            XCTAssertEqual(try Process.checkNonZeroExit(arguments: exec), "88888\n")
            // The branch of edited package should be the one we provided when putting it in edit mode.
            let editsRepo = GitRepository(path: editsPath)
            XCTAssertEqual(try editsRepo.currentBranch(), "bugfix")

            // It shouldn't be possible to unedit right now because of uncommited changes.
            do {
                _ = try SwiftPMProduct.SwiftPackage.execute(["unedit", "bar"], packagePath: fooPath)
                XCTFail("Unexpected unedit success")
            } catch {}

            try editsRepo.stageEverything()
            try editsRepo.commit()

            // It shouldn't be possible to unedit right now because of unpushed changes.
            do {
                _ = try SwiftPMProduct.SwiftPackage.execute(["unedit", "bar"], packagePath: fooPath)
                XCTFail("Unexpected unedit success")
            } catch {}

            // Push the changes.
            try editsRepo.push(remote: "origin", branch: "bugfix")

            // We should be able to unedit now.
            _ = try SwiftPMProduct.SwiftPackage.execute(["unedit", "bar"], packagePath: fooPath)

            // Test editing with a path i.e. ToT development.
            let bazTot = prefix.appending(component: "tot")
            try SwiftPMProduct.SwiftPackage.execute(["edit", "baz", "--path", bazTot.pathString], packagePath: fooPath)
            XCTAssertTrue(localFileSystem.exists(bazTot))
            XCTAssertTrue(localFileSystem.isSymlink(bazEditsPath))

            // Edit a file in baz ToT checkout.
            let bazTotPackageFile = bazTot.appending(component: "Package.swift")
            let stream = BufferedOutputByteStream()
            stream <<< (try localFileSystem.readFileContents(bazTotPackageFile)) <<< "\n// Edited."
            try localFileSystem.writeFileContents(bazTotPackageFile, bytes: stream.bytes)

            // Unediting baz will remove the symlink but not the checked out package.
            try SwiftPMProduct.SwiftPackage.execute(["unedit", "baz"], packagePath: fooPath)
            XCTAssertTrue(localFileSystem.exists(bazTot))
            XCTAssertFalse(localFileSystem.isSymlink(bazEditsPath))

            // Check that on re-editing with path, we don't make a new clone.
            try SwiftPMProduct.SwiftPackage.execute(["edit", "baz", "--path", bazTot.pathString], packagePath: fooPath)
            XCTAssertTrue(localFileSystem.isSymlink(bazEditsPath))
            XCTAssertEqual(try localFileSystem.readFileContents(bazTotPackageFile), stream.bytes)
        }
    }

    func testPackageClean() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            // Build it.
            XCTAssertBuilds(packageRoot)
            let buildPath = packageRoot.appending(component: ".build")
            let binFile = buildPath.appending(components: Resources.default.toolchain.triple.tripleString, "debug", "Bar")
            XCTAssertFileExists(binFile)
            XCTAssert(localFileSystem.isDirectory(buildPath))

            // Clean, and check for removal of the build directory but not Packages.
            _ = try execute(["clean"], packagePath: packageRoot)
            XCTAssert(!localFileSystem.exists(binFile))
            // Clean again to ensure we get no error.
            _ = try execute(["clean"], packagePath: packageRoot)
        }
    }

    func testPackageReset() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            // Build it.
            XCTAssertBuilds(packageRoot)
            let buildPath = packageRoot.appending(component: ".build")
            let binFile = buildPath.appending(components: Resources.default.toolchain.triple.tripleString, "debug", "Bar")
            XCTAssertFileExists(binFile)
            XCTAssert(localFileSystem.isDirectory(buildPath))
            // Clean, and check for removal of the build directory but not Packages.

            _ = try execute(["clean"], packagePath: packageRoot)
            XCTAssert(!localFileSystem.exists(binFile))
            XCTAssertFalse(try localFileSystem.getDirectoryContents(buildPath.appending(component: "repositories")).isEmpty)

            // Fully clean.
            _ = try execute(["reset"], packagePath: packageRoot)
            XCTAssertFalse(localFileSystem.isDirectory(buildPath))

            // Test that we can successfully run reset again.
            _ = try execute(["reset"], packagePath: packageRoot)
        }
    }

    func testPinningBranchAndRevision() throws {
        fixture(name: "Miscellaneous/PackageEdit") { prefix in
            let fooPath = prefix.appending(component: "foo")

            @discardableResult
            func execute(_ args: String..., printError: Bool = true) throws -> String {
                return try SwiftPMProduct.SwiftPackage.execute([] + args, packagePath: fooPath).stdout
            }

            try execute("update")

            let pinsFile = fooPath.appending(component: "Package.resolved")
            XCTAssert(localFileSystem.exists(pinsFile))

            // Update bar repo.
            let barPath = prefix.appending(component: "bar")
            let barRepo = GitRepository(path: barPath)
            try barRepo.checkout(newBranch: "YOLO")
            let yoloRevision = try barRepo.getCurrentRevision()

            // Try to pin bar at a branch.
            do {
                try execute("resolve", "bar", "--branch", "YOLO")
                let pinsStore = try PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                let state = CheckoutState(revision: yoloRevision, branch: "YOLO")
                XCTAssertEqual(pinsStore.pinsMap["bar"]!.state, state)
            }

            // Try to pin bar at a revision.
            do {
                try execute("resolve", "bar", "--revision", yoloRevision.identifier)
                let pinsStore = try PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                let state = CheckoutState(revision: yoloRevision)
                XCTAssertEqual(pinsStore.pinsMap["bar"]!.state, state)
            }

            // Try to pin bar at a bad revision.
            do {
                try execute("resolve", "bar", "--revision", "xxxxx")
                XCTFail()
            } catch {}
        }
    }

    func testPinning() throws {
        fixture(name: "Miscellaneous/PackageEdit") { prefix in
            let fooPath = prefix.appending(component: "foo")
            func build() throws -> String {
                return try SwiftPMProduct.SwiftBuild.execute([], packagePath: fooPath).stdout
            }
            let exec = [fooPath.appending(components: ".build", Resources.default.toolchain.triple.tripleString, "debug", "foo").pathString]

            // Build and sanity check.
            _ = try build()
            XCTAssertEqual(try Process.checkNonZeroExit(arguments: exec).spm_chomp(), "\(5)")

            // Get path to bar checkout.
            let barPath = try SwiftPMProduct.packagePath(for: "bar", packageRoot: fooPath)

            // Checks the content of checked out bar.swift.
            func checkBar(_ value: Int, file: StaticString = #file, line: UInt = #line) throws {
                let contents = try localFileSystem.readFileContents(barPath.appending(components:"Sources", "bar.swift")).validDescription?.spm_chomp()
                XCTAssert(contents?.hasSuffix("\(value)") ?? false, file: file, line: line)
            }

            // We should see a pin file now.
            let pinsFile = fooPath.appending(component: "Package.resolved")
            XCTAssert(localFileSystem.exists(pinsFile))

            // Test pins file.
            do {
                let pinsStore = try PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                XCTAssertEqual(pinsStore.pins.map{$0}.count, 2)
                for pkg in ["bar", "baz"] {
                    let pin = pinsStore.pinsMap[pkg]!
                    XCTAssertEqual(pin.packageRef.identity, pkg)
                    XCTAssert(pin.packageRef.repository.url.hasSuffix(pkg))
                    XCTAssertEqual(pin.state.version, "1.2.3")
                }
            }

            @discardableResult
            func execute(_ args: String...) throws -> String {
                return try SwiftPMProduct.SwiftPackage.execute([] + args, packagePath: fooPath).stdout
            }

            // Try to pin bar.
            do {
                try execute("resolve", "bar")
                let pinsStore = try PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
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

            // Running package update with --repin should update the package.
            do {
                try execute("update")
                try checkBar(6)
            }

            // We should be able to revert to a older version.
            do {
                try execute("resolve", "bar", "--version", "1.2.3")
                let pinsStore = try PinsStore(pinsFile: pinsFile, fileSystem: localFileSystem)
                XCTAssertEqual(pinsStore.pinsMap["bar"]!.state.version, "1.2.3")
                try checkBar(5)
            }

            // Try pinning a dependency which is in edit mode.
            do {
                try execute("edit", "bar", "--branch", "bugfix")
                do {
                    try execute("resolve", "bar")
                    XCTFail("This should have been an error")
                } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                    XCTAssertEqual(stderr, "error: dependency 'bar' already in edit mode\n")
                }
                try execute("unedit", "bar")
            }
        }
    }

    func testSymlinkedDependency() {
        mktmpdir { path in
            let fs = localFileSystem
            let root = path.appending(components: "root")
            let dep = path.appending(components: "dep")
            let depSym = path.appending(components: "depSym")

            // Create root package.
            try fs.writeFileContents(root.appending(components: "Sources", "root", "main.swift")) { $0 <<< "" }
            try fs.writeFileContents(root.appending(component: "Package.swift")) {
                $0 <<< """
                // swift-tools-version:4.2
                import PackageDescription
                let package = Package(
                name: "root",
                dependencies: [.package(url: "../depSym", from: "1.0.0")],
                targets: [.target(name: "root", dependencies: ["dep"])]
                )

                """
            }

            // Create dependency.
            try fs.writeFileContents(dep.appending(components: "Sources", "dep", "lib.swift")) { $0 <<< "" }
            try fs.writeFileContents(dep.appending(component: "Package.swift")) {
                $0 <<< """
                // swift-tools-version:4.2
                import PackageDescription
                let package = Package(
                name: "dep",
                products: [.library(name: "dep", targets: ["dep"])],
                targets: [.target(name: "dep")]
                )
                """
            }
            do {
                let depGit = GitRepository(path: dep)
                try depGit.create()
                try depGit.stageEverything()
                try depGit.commit()
                try depGit.tag(name: "1.0.0")
            }

            // Create symlink to the dependency.
            try createSymlink(depSym, pointingAt: dep)

            _ = try execute(["resolve"], packagePath: root)
        }
    }

    func testWatchmanXcodeprojgen() {
        mktmpdir { path in
            let fs = localFileSystem
            let diagnostics = DiagnosticsEngine()

            let scriptsDir = path.appending(component: "scripts")
            let packageRoot = path.appending(component: "root")

            let helper = WatchmanHelper(
                diagnostics: diagnostics,
                watchmanScriptsDir: scriptsDir,
                packageRoot: packageRoot)

            let script = try helper.createXcodegenScript(
                XcodeprojOptions(xcconfigOverrides: .init("/tmp/overrides.xcconfig")))

            XCTAssertEqual(try fs.readFileContents(script), """
                #!/usr/bin/env bash


                # Autogenerated by SwiftPM. Do not edit!


                set -eu

                swift package generate-xcodeproj --xcconfig-overrides /tmp/overrides.xcconfig

                """)
        }
    }

    func testMirrorConfig() {
        mktmpdir { prefix in
            let fs = localFileSystem
            let packageRoot = prefix.appending(component: "Foo")
            let configOverride = prefix.appending(component: "configoverride")
            let configFile = packageRoot.appending(components: ".swiftpm", "config")

            fs.createEmptyFiles(at: packageRoot, files:
                "/Sources/Foo/Foo.swift",
                "/Tests/FooTests/FooTests.swift",
                "/Package.swift",
                "anchor"
            )

            // Test writing.
            var (stdout, stderr) = try execute(["config", "set-mirror", "--package-url", "https://github.com/foo/bar", "--mirror-url", "https://mygithub.com/foo/bar"], packagePath: packageRoot)
            XCTAssertMatch(stderr, .contains("warning: '--package-url' option is deprecated; use '--original-url' instead"))
            try execute(["config", "set-mirror", "--original-url", "git@github.com:apple/swift-package-manager.git", "--mirror-url", "git@mygithub.com:foo/swift-package-manager.git"], packagePath: packageRoot)
            XCTAssertTrue(fs.isFile(configFile))

            // Test env override.
            try execute(["config", "set-mirror", "--original-url", "https://github.com/foo/bar", "--mirror-url", "https://mygithub.com/foo/bar"], packagePath: packageRoot, env: ["SWIFTPM_MIRROR_CONFIG": configOverride.pathString])
            XCTAssertTrue(fs.isFile(configOverride))
            XCTAssertTrue(try fs.readFileContents(configOverride).description.contains("mygithub"))

            // Test reading.
            (stdout, stderr) = try execute(["config", "get-mirror", "--package-url", "https://github.com/foo/bar"], packagePath: packageRoot)
            XCTAssertEqual(stdout.spm_chomp(), "https://mygithub.com/foo/bar")
            XCTAssertMatch(stderr, .contains("warning: '--package-url' option is deprecated; use '--original-url' instead"))
            (stdout, _) = try execute(["config", "get-mirror", "--original-url", "git@github.com:apple/swift-package-manager.git"], packagePath: packageRoot)
            XCTAssertEqual(stdout.spm_chomp(), "git@mygithub.com:foo/swift-package-manager.git")

            func check(stderr: String, _ block: () throws -> ()) {
                do {
                    try block()
                    XCTFail()
                } catch SwiftPMProductError.executionFailure(_, _, let stderrOutput) {
                    XCTAssertEqual(stderrOutput, stderr)
                } catch {
                    XCTFail("unexpected error: \(error)")
                }
            }

            check(stderr: "not found\n") {
                try execute(["config", "get-mirror", "--original-url", "foo"], packagePath: packageRoot)
            }

            // Test deletion.
            (_, stderr) = try execute(["config", "unset-mirror", "--package-url", "https://github.com/foo/bar"], packagePath: packageRoot)
            XCTAssertMatch(stderr, .contains("warning: '--package-url' option is deprecated; use '--original-url' instead"))
            try execute(["config", "unset-mirror", "--original-url", "git@mygithub.com:foo/swift-package-manager.git"], packagePath: packageRoot)

            check(stderr: "not found\n") {
                try execute(["config", "get-mirror", "--original-url", "https://github.com/foo/bar"], packagePath: packageRoot)
            }
            check(stderr: "not found\n") {
                try execute(["config", "get-mirror", "--original-url", "git@github.com:apple/swift-package-manager.git"], packagePath: packageRoot)
            }

            check(stderr: "error: mirror not found\n") {
                try execute(["config", "unset-mirror", "--original-url", "foo"], packagePath: packageRoot)
            }
        }
    }
    
    func testPackageLoadingCommandPathResilience() throws {
      #if os(macOS)
        fixture(name: "ValidLayouts/SingleModule") { prefix in
            mktmpdir { tmpdir in
                // Create fake `xcrun` and `sandbox-exec` commands.
                let fakeBinDir = tmpdir
                for fakeCmdName in ["xcrun", "sandbox-exec"] {
                    let fakeCmdPath = fakeBinDir.appending(component: fakeCmdName)
                    try localFileSystem.writeFileContents(fakeCmdPath, body: { stream in
                        stream <<< """
                        #!/bin/sh
                        echo "wrong \(fakeCmdName) invoked"
                        exit 1
                        """
                    })
                    try localFileSystem.chmod(.executable, path: fakeCmdPath)
                }
                
                // Invoke `swift-package`, passing in the overriding `PATH` environment variable.
                let packageRoot = prefix.appending(component: "Library")
                let patchedPATH = fakeBinDir.pathString + ":" + ProcessInfo.processInfo.environment["PATH"]!
                let result = try SwiftPMProduct.SwiftPackage.executeProcess(["dump-package"], packagePath: packageRoot, env: ["PATH": patchedPATH])
                let textOutput = try result.utf8Output() + result.utf8stderrOutput()
                
                // Check that the wrong tools weren't invoked.  We can't just check the exit code because of fallbacks.
                XCTAssertNoMatch(textOutput, .contains("wrong xcrun invoked"))
                XCTAssertNoMatch(textOutput, .contains("wrong sandbox-exec invoked"))
            }
        }
      #endif
    }
}
