/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */
import XCTest

import PackageGraph
import PackageModel
import TSCBasic
import struct TSCUtility.Version

public struct MockDependencyGraph {
    public let name: String
    public let constraints: [MockPackageContainer.Constraint]
    public let containers: [MockPackageContainer]
    public let result: [PackageReference: Version]

    public func checkResult(
        _ output: [(container: PackageReference, version: Version)],
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

// MARK: - JSON

public extension MockDependencyGraph {
    init(_ json: JSON) {
        guard case .dictionary(let dict) = json else { fatalError() }
        guard case .string(let name)? = dict["name"] else { fatalError() }
        guard case .array(let constraints)? = dict["constraints"] else { fatalError() }
        guard case .array(let containers)? = dict["containers"] else { fatalError() }
        guard case .dictionary(let result)? = dict["result"] else { fatalError() }

        self.result = Dictionary(uniqueKeysWithValues: result.map { value in
            let (container, version) = value
            guard case .string(let str) = version else { fatalError() }
            let package = PackageReference(identity: PackageIdentity(url: container.lowercased()), path: "/\(container)")
            return (package, Version(string: str)!)
        })
        self.name = name
        self.constraints = constraints.map(PackageContainerConstraint.init(json:))
        self.containers = containers.map(MockPackageContainer.init(json:))
    }
}

private extension MockPackageContainer {
    convenience init(json: JSON) {
        guard case .dictionary(let dict) = json else { fatalError() }
        guard case .string(let identifier)? = dict["identifier"] else { fatalError() }
        guard case .dictionary(let versions)? = dict["versions"] else { fatalError() }

        var depByVersion: [Version: [(container: String, versionRequirement: VersionSetSpecifier)]] = [:]
        for (version, deps) in versions {
            guard case .array(let depArray) = deps else { fatalError() }
            depByVersion[Version(string: version)!] = depArray
                .map(PackageContainerConstraint.init(json:))
                .map { constraint in
                    switch constraint.requirement {
                    case .versionSet(let versionSet):
                        return (constraint.identifier.identity.description, versionSet)
                    case .unversioned:
                        fatalError()
                    case .revision:
                        fatalError()
                    }
                }
        }

        self.init(name: identifier, dependenciesByVersion: depByVersion)
    }
}

private extension MockPackageContainer.Constraint {
    init(json: JSON) {
        guard case .dictionary(let dict) = json else { fatalError() }
        guard case .string(let identifier)? = dict["identifier"] else { fatalError() }
        guard let requirement = dict["requirement"] else { fatalError() }
        let products: ProductFilter = try! JSON(dict).get("products")
        let id = PackageReference(identity: PackageIdentity(url: identifier), path: "", kind: .remote)
        self.init(container: id, versionRequirement: VersionSetSpecifier(requirement), products: products)
    }
}

private extension VersionSetSpecifier {
    init(_ json: JSON) {
        switch json {
        case .string(let str):
            switch str {
            case "any": self = .any
            case "empty": self = .empty
            default: fatalError()
            }
        case .array(let arr):
            switch arr.count {
            case 1:
                guard case .string(let str) = arr[0] else { fatalError() }
                self = .exact(Version(string: str)!)
            case 2:
                let versions = arr.map { json -> Version in
                    guard case .string(let str) = json else { fatalError() }
                    return Version(string: str)!
                }
                self = .range(versions[0] ..< versions[1])
            default: fatalError()
            }
        default: fatalError()
        }
    }
}
