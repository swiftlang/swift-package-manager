/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import struct PackageDescription.Version
@testable import Get
import struct PackageType.Manifest
import class PackageType.Package
import XCTest
import Utility

typealias Sandbox = PackagesDirectory


class GetTests: XCTestCase {

    func testRawCloneDoesNotCrashIfManifestIsNotPresent() {
        mktmpdir { tmpdir in
            guard let repo = makeGitRepo(tmpdir, tag: "0.1.0") else { return XCTFail() }
            try popen(["git", "-C", repo.path, "remote", "add", "origin", repo.path])
            let clone = try RawClone(path: repo.path, manifestParser: { _,_ throws -> Manifest in
                throw Package.Error.NoManifest(tmpdir)
            })
            XCTAssertEqual(clone.children.count, 0)
        }
    }
    
    func testRangeConstrain() {
        let r1 = Version(2, 0, 0)..<Version(3, 0, 0)
        let r2 = Version(1, 0, 0)..<Version(2, 0, 0)
        let r3 = Version(1, 0, 0)...Version(2, 0, 0)
        let r4 = Version(1, 5, 0)..<Version(2, 5, 0)
        let r5 = Version(2, 5, 0)..<Version(2, 6, 0)
        let r6 = Version(2, 5, 0)..<Version(3, 5, 0)
        let r7 = Version(3, 0, 0)..<Version(4, 0, 0)
        let r8 = Version(1, 0, 0)..<Version(4, 0, 0)
        
        let r12: Range<Version>? = nil
        let r13 = r1.startIndex...r1.startIndex
        let r14 = r1.startIndex..<r4.endIndex
        let r15 = r5
        let r16 = r6.startIndex..<r1.endIndex
        let r17: Range<Version>? = nil
        let r18 = r1
        
        XCTAssertEqual(r1.constrain(to: r2), r12)
        XCTAssertEqual(r2.constrain(to: r1), r12)
        XCTAssertEqual(r1.constrain(to: r3), r13)
        XCTAssertEqual(r3.constrain(to: r1), r13)
        XCTAssertEqual(r1.constrain(to: r4), r14)
        XCTAssertEqual(r4.constrain(to: r1), r14)
        XCTAssertEqual(r1.constrain(to: r5), r15)
        XCTAssertEqual(r5.constrain(to: r1), r15)
        XCTAssertEqual(r1.constrain(to: r6), r16)
        XCTAssertEqual(r6.constrain(to: r1), r16)
        XCTAssertEqual(r1.constrain(to: r7), r17)
        XCTAssertEqual(r7.constrain(to: r1), r17)
        XCTAssertEqual(r1.constrain(to: r8), r18)
        XCTAssertEqual(r8.constrain(to: r1), r18)
    }

    func testGitRepoInitialization() {

        fixture(name: "DependencyResolution/External/Complex") { prefix in
            XCTAssertNotNil(Git.Repo(path: Path.join(prefix, "app")))
        }

        XCTAssertNil(Git.Repo(path: #file))
        XCTAssertNil(Git.Repo(path: #file.parentDirectory))
    }

    //TODO enable
//    func testTransmuteResolvesCModuleDependencies() {
//        fixture(name: "Miscellaneous/PackageType") { prefix in
//            let prefix = Path.join(prefix, "App")
//            let manifest = try Manifest(path: prefix)
//            let (rootPackage, externalPackages) = try get(manifest, manifestParser: { try Manifest(path: $0, baseURL: $1) })
//            let (modules, _,  _) = try transmute(rootPackage, externalPackages: externalPackages)
//
//            XCTAssertEqual(modules.count, 3)
//            XCTAssertEqual(recursiveDependencies(modules).count, 3)
//            XCTAssertTrue(modules.dropFirst().first is CModule)
//        }
//
//        fixture(name: "ModuleMaps/Direct") { prefix in
//            let prefix = Path.join(prefix, "App")
//            let manifest = try Manifest(path: prefix)
//            let (rootPackage, externalPackages) = try get(manifest, manifestParser: { try Manifest(path: $0, baseURL: $1) })
//            let (modules, _,  _) = try transmute(rootPackage, externalPackages: externalPackages)
//
//            XCTAssertEqual(modules.count, 2)
//            XCTAssertTrue(modules.first is CModule)
//            XCTAssertEqual(modules[1].dependencies.count, 1)
//            XCTAssertEqual(modules[1].recursiveDependencies.count, 1)
//            XCTAssertTrue(modules[1].dependencies.contains(modules[0]))
//        }
//    }
}


