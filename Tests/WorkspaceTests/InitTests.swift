/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import SPMTestSupport
import TSCBasic
import PackageModel
import Workspace
import Commands

class InitTests: XCTestCase {

    // MARK: TSCBasic package creation for each package type.
    
    func testInitPackageEmpty() throws {
        mktmpdir { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            let name = path.basename
            try fs.createDirectory(path)
            
            // Create the package
            let initPackage = try InitPackage(name: name, destinationPath: path, packageType: InitPackage.PackageType.empty)
            var progressMessages = [String]()
            initPackage.progressReporter = { message in
                progressMessages.append(message)
            }
            try initPackage.writePackageStructure()

            // Not picky about the specific progress messages, just checking that we got some.
            XCTAssert(progressMessages.count > 0)

            // Verify basic file system content that we expect in the package
            let manifest = path.appending(component: "Package.swift")
            XCTAssertTrue(fs.exists(manifest))
            let manifestContents = try localFileSystem.readFileContents(manifest).description
            let version = "\(InitPackage.newPackageToolsVersion.major).\(InitPackage.newPackageToolsVersion.minor)"
            XCTAssertTrue(manifestContents.hasPrefix("// swift-tools-version:\(version)\n"))
            XCTAssertTrue(manifestContents.contains(packageWithNameAndDependencies(with: name)))
            XCTAssert(fs.exists(path.appending(component: "README.md")))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources")), [])
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Tests")), [])
        }
    }
    
    func testInitPackageExecutable() throws {
        mktmpdir { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            let initPackage = try InitPackage(name: name, destinationPath: path, packageType: InitPackage.PackageType.executable)
            var progressMessages = [String]()
            initPackage.progressReporter = { message in
                progressMessages.append(message)
            }
            try initPackage.writePackageStructure()

            // Not picky about the specific progress messages, just checking that we got some.
            XCTAssert(progressMessages.count > 0)

            
            // Verify basic file system content that we expect in the package
            let manifest = path.appending(component: "Package.swift")
            XCTAssertTrue(fs.exists(manifest))
            let manifestContents = try localFileSystem.readFileContents(manifest).description
            let version = "\(InitPackage.newPackageToolsVersion.major).\(InitPackage.newPackageToolsVersion.minor)"
            XCTAssertTrue(manifestContents.hasPrefix("// swift-tools-version:\(version)\n"))
            
            let readme = path.appending(component: "README.md")
            XCTAssertTrue(fs.exists(readme))
            let readmeContents = try localFileSystem.readFileContents(readme).description
            XCTAssertTrue(readmeContents.hasPrefix("# Foo\n"))

            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources").appending(component: "Foo")), ["main.swift"])
            XCTAssertEqual(
                try fs.getDirectoryContents(path.appending(component: "Tests")).sorted(),
                ["FooTests", "LinuxMain.swift"])
            
            // Try building it
            XCTAssertBuilds(path)
            let triple = Resources.default.toolchain.triple
            let binPath = path.appending(components: ".build", triple.tripleString, "debug")
            XCTAssertFileExists(binPath.appending(component: "Foo"))
            XCTAssertFileExists(binPath.appending(component: "Foo.swiftmodule"))
        }
    }

    func testInitPackageLibrary() throws {
        mktmpdir { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            let initPackage = try InitPackage(name: name, destinationPath: path, packageType: InitPackage.PackageType.library)
            var progressMessages = [String]()
            initPackage.progressReporter = { message in
                progressMessages.append(message)
            }
            try initPackage.writePackageStructure()

            // Not picky about the specific progress messages, just checking that we got some.
            XCTAssert(progressMessages.count > 0)

            // Verify basic file system content that we expect in the package
            let manifest = path.appending(component: "Package.swift")
            XCTAssertTrue(fs.exists(manifest))
            let manifestContents = try localFileSystem.readFileContents(manifest).description
            let version = "\(InitPackage.newPackageToolsVersion.major).\(InitPackage.newPackageToolsVersion.minor)"
            XCTAssertTrue(manifestContents.hasPrefix("// swift-tools-version:\(version)\n"))

            let readme = path.appending(component: "README.md")
            XCTAssertTrue(fs.exists(readme))
            let readmeContents = try localFileSystem.readFileContents(readme).description
            XCTAssertTrue(readmeContents.hasPrefix("# Foo\n"))

            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources").appending(component: "Foo")), ["Foo.swift"])
            XCTAssertEqual(
                try fs.getDirectoryContents(path.appending(component: "Tests")).sorted(),
                ["FooTests", "LinuxMain.swift"])

            // Try building it
            XCTAssertBuilds(path)
            let triple = Resources.default.toolchain.triple
            XCTAssertFileExists(path.appending(components: ".build", triple.tripleString, "debug", "Foo.swiftmodule"))
        }
    }
    
    func testInitPackageSystemModule() throws {
        mktmpdir { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            let name = path.basename
            try fs.createDirectory(path)
            
            // Create the package
            let initPackage = try InitPackage(name: name, destinationPath: path, packageType: InitPackage.PackageType.systemModule)
            var progressMessages = [String]()
            initPackage.progressReporter = { message in
                progressMessages.append(message)
            }
            try initPackage.writePackageStructure()
            
            // Not picky about the specific progress messages, just checking that we got some.
            XCTAssert(progressMessages.count > 0)

            // Verify basic file system content that we expect in the package
            let manifest = path.appending(component: "Package.swift")
            XCTAssertTrue(fs.exists(manifest))
            let manifestContents = try localFileSystem.readFileContents(manifest).description
            let version = "\(InitPackage.newPackageToolsVersion.major).\(InitPackage.newPackageToolsVersion.minor)"
            XCTAssertTrue(manifestContents.hasPrefix("// swift-tools-version:\(version)\n"))
            XCTAssertTrue(manifestContents.contains(packageWithNameAndDependencies(with: name)))
            XCTAssert(fs.exists(path.appending(component: "README.md")))
            XCTAssert(fs.exists(path.appending(component: "module.modulemap")))
        }
    }

    func testInitManifest() throws {
        mktmpdir { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            let initPackage = try InitPackage(name: name, destinationPath: path, packageType: InitPackage.PackageType.manifest)
            var progressMessages = [String]()
            initPackage.progressReporter = { message in
                progressMessages.append(message)
            }
            try initPackage.writePackageStructure()

            // Not picky about the specific progress messages, just checking that we got some.
            XCTAssert(progressMessages.count > 0)

            // Verify basic file system content that we expect in the package
            let manifest = path.appending(component: "Package.swift")
            XCTAssertTrue(fs.exists(manifest))
            let manifestContents = try localFileSystem.readFileContents(manifest).description
            let version = "\(InitPackage.newPackageToolsVersion.major).\(InitPackage.newPackageToolsVersion.minor)"
            XCTAssertTrue(manifestContents.hasPrefix("// swift-tools-version:\(version)\n"))
        }
    }
    
    // MARK: Special case testing
    
    func testInitPackageNonc99Directory() throws {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            XCTAssertTrue(localFileSystem.isDirectory(tempDirPath))
            
            // Create a directory with non c99name.
            let packageRoot = tempDirPath.appending(component: "some-package")
            let packageName = packageRoot.basename
            try localFileSystem.createDirectory(packageRoot)
            XCTAssertTrue(localFileSystem.isDirectory(packageRoot))
            
            // Create the package
            let initPackage = try InitPackage(name: packageName, destinationPath: packageRoot, packageType: InitPackage.PackageType.library)
            initPackage.progressReporter = { message in
            }
            try initPackage.writePackageStructure()

            // Try building it.
            XCTAssertBuilds(packageRoot)
            let triple = Resources.default.toolchain.triple
            XCTAssertFileExists(packageRoot.appending(components: ".build", triple.tripleString, "debug", "some_package.swiftmodule"))
        }
    }
    
    func testNonC99NameExecutablePackage() throws {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            XCTAssertTrue(localFileSystem.isDirectory(tempDirPath))
            
            let packageRoot = tempDirPath.appending(component: "Foo")
            try localFileSystem.createDirectory(packageRoot)
            XCTAssertTrue(localFileSystem.isDirectory(packageRoot))
            
            // Create package with non c99name.
            let initPackage = try InitPackage(name: "package-name", destinationPath: packageRoot, packageType: InitPackage.PackageType.executable)
            try initPackage.writePackageStructure()
            
            #if os(macOS)
              XCTAssertSwiftTest(packageRoot)
            #else
              XCTAssertBuilds(packageRoot)
            #endif
        }
    }

    func testXCTestManifestOption() throws {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            var options = InitPackage.InitPackageOptions(packageType: .library)

            func assertTestManifestFiles(options: InitPackage.InitPackageOptions, expected: Bool) throws {
                let packageRoot = tempDirPath.appending(component: "Foo")
                try localFileSystem.removeFileTree(packageRoot)
                try localFileSystem.createDirectory(packageRoot)

                let initPackage = try InitPackage(
                    name: "Foo",
                    destinationPath: packageRoot,
                    options: options
                )
                var progressMessages = [String]()
                initPackage.progressReporter = { message in
                    progressMessages.append(message)
                }
                try initPackage.writePackageStructure()

                let linuxMain = packageRoot.appending(RelativePath("Tests/LinuxMain.swift"))
                let xctManifest = packageRoot.appending(RelativePath("Tests/FooTests/XCTestManifests.swift"))

                XCTAssertEqual(localFileSystem.isFile(linuxMain), expected, "\(progressMessages)")
                XCTAssertEqual(localFileSystem.isFile(xctManifest), expected, "\(progressMessages)")
            }

            options.enableXCTestManifest = true
            try assertTestManifestFiles(options: options, expected: true)

            options.enableXCTestManifest = false
            try assertTestManifestFiles(options: options, expected: false)
        }
    }

    func testPlatforms() throws {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            var options = InitPackage.InitPackageOptions(packageType: .library)
            options.platforms = [
                .init(platform: .macOS, version: PlatformVersion("10.15")),
                .init(platform: .iOS, version: PlatformVersion("12")),
                .init(platform: .watchOS, version: PlatformVersion("2.1")),
                .init(platform: .tvOS, version: PlatformVersion("999")),
            ]

            let packageRoot = tempDirPath.appending(component: "Foo")
            try localFileSystem.removeFileTree(packageRoot)
            try localFileSystem.createDirectory(packageRoot)

            let initPackage = try InitPackage(
                name: "Foo",
                destinationPath: packageRoot,
                options: options
            )
            try initPackage.writePackageStructure()

            let contents = try localFileSystem.readFileContents(packageRoot.appending(component: "Package.swift")).cString
            let expectedString = #"platforms: [.macOS(.v10_15), .iOS(.v12), .watchOS("2.1"), .tvOS("999.0")],"#
            XCTAssert(contents.contains(expectedString), contents)
        }
    }

    private func packageWithNameAndDependencies(with name: String) -> String {
        return """
let package = Package(
    name: "\(name)",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ]
)
"""
    }
}
