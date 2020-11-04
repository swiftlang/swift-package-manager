/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */
import XCTest

import PackageGraph
import TSCBasic
import struct TSCUtility.Version

public struct MockDependencyGraph {
    public let name: String
    public let constraints: [MockPackageConstraint]
    public let containers: [MockPackageContainer]
    public let result: [String: Version]

    public init(_ json: JSON) {
        guard case .dictionary(let dict) = json else { fatalError() }
        guard case .string(let name)? = dict["name"] else { fatalError() }
        guard case .array(let constraints)? = dict["constraints"] else { fatalError() }
        guard case .array(let containers)? = dict["containers"] else { fatalError() }
        guard case .dictionary(let result)? = dict["result"] else { fatalError() }

        self.result = Dictionary(uniqueKeysWithValues: result.map { value in
            let (container, version) = value
            guard case .string(let str) = version else { fatalError() }
            return (container.lowercased(), Version(string: str)!)
        })
        self.name = name
        self.constraints = constraints.map(PackageContainerConstraint.init(json:))
        self.containers = containers.map(MockPackageContainer.init(json:))
    }

    public func checkResult(
        _ output: [(container: String, version: Version)],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        var result = self.result
        for item in output {
            XCTAssertEqual(result[item.container], item.version, file: file, line: line)
            result[item.container] = nil
        }
        if !result.isEmpty {
            XCTFail("Unchecked containers: \(result)", file: file, line: line)
        }
    }
}
