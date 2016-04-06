/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Transmute
import struct Utility.Path
import ManifestParser
import PackageType
import XCTest

enum ModuleType { case Library }

extension Module {
    private convenience init(name: String, files: [String], type: ModuleType) {
        self.init(name: name)
    }

    private func dependsOn(_ target: Module) {
        dependencies.append(target)
    }

    var recursiveDeps: [Module] {
        sort(self)
        return dependencies
    }
}


class ModuleTests: XCTestCase {

    func test1() {
        let t1 = Module(name: "t1")
        let t2 = Module(name: "t2")
        let t3 = Module(name: "t3")

        t3.dependsOn(t2)
        t2.dependsOn(t1)

        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test2() {
        let t1 = Module(name: "t1")
        let t2 = Module(name: "t2")
        let t3 = Module(name: "t3")
        let t4 = Module(name: "t3")

        t4.dependsOn(t2)
        t4.dependsOn(t3)
        t4.dependsOn(t1)
        t3.dependsOn(t2)
        t3.dependsOn(t1)
        t2.dependsOn(t1)

        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test3() {
        let t1 = Module(name: "t1")
        let t2 = Module(name: "t2")
        let t3 = Module(name: "t3")
        let t4 = Module(name: "t4")

        t4.dependsOn(t1)
        t4.dependsOn(t2)
        t4.dependsOn(t3)
        t3.dependsOn(t2)
        t3.dependsOn(t1)
        t2.dependsOn(t1)

        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test4() {
        let t1 = Module(name: "t1")
        let t2 = Module(name: "t2")
        let t3 = Module(name: "t3")
        let t4 = Module(name: "t4")

        t4.dependsOn(t3)
        t3.dependsOn(t2)
        t2.dependsOn(t1)

        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test5() {
        let t1 = Module(name: "t1")
        let t2 = Module(name: "t2")
        let t3 = Module(name: "t3")
        let t4 = Module(name: "t4")
        let t5 = Module(name: "t5")
        let t6 = Module(name: "t6")

        t6.dependsOn(t5)
        t6.dependsOn(t4)
        t5.dependsOn(t2)
        t4.dependsOn(t3)
        t3.dependsOn(t2)
        t2.dependsOn(t1)

        // precise order is not important, but it is important that the following are true
        let t6rd = t6.recursiveDeps
        XCTAssertEqual(t6rd.index(of: t3)!, t6rd.index(of: t4)!.successor())
        XCTAssert(t6rd.index(of: t5)! < t6rd.index(of: t2)!)
        XCTAssert(t6rd.index(of: t5)! < t6rd.index(of: t1)!)
        XCTAssert(t6rd.index(of: t2)! < t6rd.index(of: t1)!)
        XCTAssert(t6rd.index(of: t3)! < t6rd.index(of: t2)!)

        XCTAssertEqual(t5.recursiveDeps, [t2, t1])
        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test6() {
        let t1 = Module(name: "t1")
        let t2 = Module(name: "t2")
        let t3 = Module(name: "t3")
        let t4 = Module(name: "t4")
        let t5 = Module(name: "t5")
        let t6 = Module(name: "t6")

        t6.dependsOn(t4)  // same as above, but
        t6.dependsOn(t5)  // these two swapped
        t5.dependsOn(t2)
        t4.dependsOn(t3)
        t3.dependsOn(t2)
        t2.dependsOn(t1)

        // precise order is not important, but it is important that the following are true
        let t6rd = t6.recursiveDeps
        XCTAssertEqual(t6rd.index(of: t3)!, t6rd.index(of: t4)!.successor())
        XCTAssert(t6rd.index(of: t5)! < t6rd.index(of: t2)!)
        XCTAssert(t6rd.index(of: t5)! < t6rd.index(of: t1)!)
        XCTAssert(t6rd.index(of: t2)! < t6rd.index(of: t1)!)
        XCTAssert(t6rd.index(of: t3)! < t6rd.index(of: t2)!)

        XCTAssertEqual(t5.recursiveDeps, [t2, t1])
        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func testIgnoresFiles() {

        // there is a hidden `.Bar.swift` file in this fixture

       fixture(name: "Miscellaneous/IgnoreDiagnostic") { prefix in
           let manifest = try Manifest(path: prefix)
           let modules = try Package(manifest: manifest, url: prefix).modules()

           XCTAssertEqual(modules.count, 1)

           guard let swiftModule = modules.first as? SwiftModule else { return XCTFail() }
           XCTAssertEqual(swiftModule.sources.paths.count, 1)
           XCTAssertEqual(swiftModule.sources.paths[0].basename, "Foo.swift")

           XCTAssertBuilds(prefix)
       }
    }

    func testModuleTypes() {
        let dummyURL = "https://example.com"

       fixture(name: "Miscellaneous/PackageType") { prefix in

           // TODO get is enough
           XCTAssertBuilds(prefix, "App")

           for module in try Package(manifest: Manifest(path: prefix, "App/Packages/Module-1.2.3"), url: dummyURL).modules() {
               XCTAssert(module is SwiftModule)
           }

           for module in try Package(manifest: Manifest(path: prefix, "App/Packages/ModuleMap-1.2.3"), url: dummyURL).modules() {
               XCTAssert(module is CModule)
           }
       }
    }
}


import Get

extension ModuleTests {
    func testTransmuteResolvesCModuleDependencies() {
        fixture(name: "Miscellaneous/PackageType") { prefix in
            let prefix = Path.join(prefix, "App")
            let manifest = try Manifest(path: prefix)
            let (rootPackage, externalPackages) = try get(manifest, manifestParser: { try Manifest(path: $0, baseURL: $1) })
            let (modules, _,  _) = try transmute(rootPackage, externalPackages: externalPackages)
            
            XCTAssertEqual(modules.count, 3)
            XCTAssertEqual(recursiveDependencies(modules).count, 3)
            XCTAssertTrue(modules.dropFirst().first is CModule)
        }

        fixture(name: "ModuleMaps/Direct") { prefix in
            let prefix = Path.join(prefix, "App")
            let manifest = try Manifest(path: prefix)
            let (rootPackage, externalPackages) = try get(manifest, manifestParser: { try Manifest(path: $0, baseURL: $1) })
            let (modules, _,  _) = try transmute(rootPackage, externalPackages: externalPackages)

            XCTAssertEqual(modules.count, 2)
            XCTAssertTrue(modules.first is CModule)
            XCTAssertEqual(modules[1].dependencies.count, 1)
            XCTAssertEqual(modules[1].recursiveDependencies.count, 1)
            XCTAssertTrue(modules[1].dependencies.contains(modules[0]))
        }
    }
}


extension ModuleTests {
    static var allTests : [(String, ModuleTests -> () throws -> Void)] {
        return [
            ("test1", test1),
            ("test2", test2),
            ("test3", test3),
            ("test4", test4),
            ("test5", test5),
            ("test6", test6),
            ("testIgnoresFiles", testIgnoresFiles),
            ("testModuleTypes", testModuleTypes),
            ("testTransmuteResolvesCModuleDependencies", testTransmuteResolvesCModuleDependencies),
        ]
    }
}

#if os(OSX)
    private func bundleRoot() -> String {
        for bundle in NSBundle.allBundles() where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundlePath.parentDirectory
        }
        fatalError()
    }
#endif

import func POSIX.getenv

extension Manifest {
    private init(path pathComponents: String..., baseURL: String! = nil) throws {

    // copy pasta from ManifestParser tests
    // TODO these tests should not depend on ManifestParser *at all* so fix that then delete this

    #if os(OSX)
        #if Xcode
            let swiftc = Path.join(getenv("XCODE_DEFAULT_TOOLCHAIN_OVERRIDE")!, "usr/bin/swiftc")
        #else
            let swiftc = Path.join(bundleRoot(), "swiftc")
        #endif
        let libdir = bundleRoot()
    #else
        let libdir = Process.arguments.first!.parentDirectory.abspath()
        let swiftc = Path.join(libdir, "swiftc")
    #endif

        let path = Path.join(pathComponents)
        let baseURL = baseURL ?? path
        try self.init(path: path, baseURL: baseURL, swiftc: swiftc, libdir: libdir)
    }
}
