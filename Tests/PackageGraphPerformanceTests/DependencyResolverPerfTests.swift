/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import PackageModel
import PackageGraph
import PackageLoading
import SourceControl

import struct TSCUtility.Version

import SPMTestSupport

private let v1: Version = "1.0.0"
private let v1Range: VersionSetSpecifier = .range("1.0.0" ..< "2.0.0")

class DependencyResolverRealWorldPerfTests: XCTestCasePerf {

    func testKituraPubGrub_X100() throws {
      #if os(macOS)
        try runPackageTestPubGrub(name: "kitura.json", N: 100)
      #endif
    }

    func testZewoPubGrub_X100() throws {
      #if os(macOS)
        try runPackageTestPubGrub(name: "ZewoHTTPServer.json", N: 100)
      #endif
    }

    func testPerfectPubGrub_X100() throws {
      #if os(macOS)
        try runPackageTestPubGrub(name: "PerfectHTTPServer.json", N: 100)
      #endif
    }

    func testSourceKittenPubGrub_X100() throws {
      #if os(macOS)
        try runPackageTestPubGrub(name: "SourceKitten.json", N: 100)
      #endif
    }

    func runPackageTestPubGrub(name: String, N: Int = 1) throws {
        let graph = try mockGraph(for: name)
        let provider = MockPackagesProvider(containers: graph.containers)

        measure {
            for _ in 0 ..< N {
                let resolver = PubgrubDependencyResolver(provider)
                switch resolver.solve(dependencies: graph.constraints) {
                case .success(let result):
                    let result: [(container: String, version: Version)] = result.compactMap {
                        guard case .version(let version) = $0.binding else {
                            XCTFail("Unexpected result")
                            return nil
                        }
                        return ($0.container.identity, version)
                    }
                    graph.checkResult(result)

                case .error:
                    XCTFail("Unexpected result")
                    return
                }
            }
        }
    }

    func mockGraph(for name: String) throws -> MockGraph {
        let input = AbsolutePath(#file).parentDirectory.appending(component: "Inputs").appending(component: name)
        let jsonString = try localFileSystem.readFileContents(input)
        let json = try JSON(bytes: jsonString)
        return MockGraph(json)
    }
}
