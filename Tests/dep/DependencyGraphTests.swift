/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import dep
@testable import struct PackageDescription.Version

class VersionGraphTests: XCTestCase {

    var allTests : [(String, () -> ())] {
        return [
            ("testNoGraph", testNoGraph),
            ("testOneDependency", testOneDependency),
            ("testOneDepenencyWithMultipleAvailableVersions", testOneDepenencyWithMultipleAvailableVersions),
            ("testOneDepenencyWithMultipleAvailableVersions", testOneDepenencyWithMultipleAvailableVersions),
            ("testTwoDependencies", testTwoDependencies),
            ("testTwoDirectDependencies", testTwoDirectDependencies),
            ("testTwoDirectDependenciesWhereOneAlsoDependsOnTheOther", testTwoDirectDependenciesWhereOneAlsoDependsOnTheOther),
            ("testSimpleVersionRestrictedGraph", testSimpleVersionRestrictedGraph),
            ("testComplexVersionRestrictedGraph", testComplexVersionRestrictedGraph),
            ("testVersionConstrain", testVersionConstrain),
            ("testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Simple", testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Simple),
            ("testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Complex", testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Complex),
            ("testVersionUnavailable", testVersionUnavailable)
        ]
    }

    func testNoGraph() {
        class MockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                    case .A: return MockCheckout(.A, [v1])
                default:
                    fatalError()
                }
            }
        }

        let rv: [MockCheckout] = try! MockFetcher().recursivelyFetch([(MockProject.A.url, v1...v1)])

        XCTAssertEqual(rv, [
            MockCheckout(.A, v1)
        ])
    }

    func testOneDependency() {
        class MockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                case .A: return MockCheckout(.A, [v1], (MockProject.B.url, v1...v1))
                case .B: return MockCheckout(.B, [v1])
                default:
                    fatalError()
                }
            }
        }

        let rv: [MockCheckout] = try! MockFetcher().recursivelyFetch([(MockProject.A.url, v1...v1)])

        XCTAssertEqual(rv, [
            MockCheckout(.B, v1),
            MockCheckout(.A, v1),
        ])
    }

    func testOneDepenencyWithMultipleAvailableVersions() {
        class MockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                    case .A: return MockCheckout(.A, [v1], (MockProject.B.url, v1..<v2))
                    case .B: return MockCheckout(.B, [v1, v199, v2, "3.0.0"])
                default:
                    fatalError()
                }
            }
        }

        let rv: [MockCheckout] = try! MockFetcher().recursivelyFetch([(MockProject.A.url, v1...v1)])

        XCTAssertEqual(rv, [
            MockCheckout(.B, v199),
            MockCheckout(.A, v1),
        ])
    }

    func testTwoDependencies() {
        class MockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                    case .A: return MockCheckout(.A, [v1], (MockProject.B.url, v1...v1))
                    case .B: return MockCheckout(.B, [v1], (MockProject.C.url, v1...v1))
                    case .C: return MockCheckout(.C, [v1])
                default:
                    fatalError()
                }
            }
        }

        let rv: [MockCheckout] = try! MockFetcher().recursivelyFetch([(MockProject.A.url, v1...v1)])

        XCTAssertEqual(rv, [
            MockCheckout(.C, v1),
            MockCheckout(.B, v1),
            MockCheckout(.A, v1)
        ])
    }

    func testTwoDirectDependencies() {
        class MockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                    case .A: return MockCheckout(.A, [v1], (MockProject.B.url, v1...v1), (MockProject.C.url, v1...v1))
                    case .B: return MockCheckout(.B, [v1])
                    case .C: return MockCheckout(.C, [v1])
                default:
                    fatalError()
                }
            }
        }

        let rv: [MockCheckout] = try! MockFetcher().recursivelyFetch([(MockProject.A.url, v1...v1)])

        XCTAssertEqual(rv, [
            MockCheckout(.B, v1),
            MockCheckout(.C, v1),
            MockCheckout(.A, v1)
        ])
    }

    func testTwoDirectDependenciesWhereOneAlsoDependsOnTheOther() {
        class MockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                    case .A: return MockCheckout(.A, [v1], (MockProject.B.url, v1...v1), (MockProject.C.url, v1...v1))
                    case .B: return MockCheckout(.B, [v1], (MockProject.C.url, v1...v1))
                    case .C: return MockCheckout(.C, [v1])
                default:
                    fatalError()
                }
            }
        }

        let rv: [MockCheckout] = try! MockFetcher().recursivelyFetch([(MockProject.A.url, v1...v1)])

        XCTAssertEqual(rv, [
            MockCheckout(.C, v1),
            MockCheckout(.B, v1),
            MockCheckout(.A, v1)
        ])
    }

    func testSimpleVersionRestrictedGraph() {

        class MockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                    case .A: return MockCheckout(.A, [v1], (MockProject.C.url, v123..<v2))
                    case .B: return MockCheckout(.B, [v2], (MockProject.C.url, v123...v126))
                    case .C: return MockCheckout(.C, [v126])
                default:
                    fatalError()
                }
            }
        }

        let rv: [MockCheckout] = try! MockFetcher().recursivelyFetch([
            (MockProject.A.url, v1...v1),
            (MockProject.B.url, v2...v2)
        ])

        XCTAssertEqual(rv, [
            MockCheckout(.C, v126),
            MockCheckout(.A, v1),
            MockCheckout(.B, v2)
        ])
    }

    func testComplexVersionRestrictedGraph() {

        class MyMockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                    case .A: return MockCheckout(.A, [v1], (MockProject.C.url, Version(1,2,3)..<v2), (MockProject.D.url, v126...v2), (MockProject.B.url, v1...v2))
                    case .B: return MockCheckout(.B, [v2], (MockProject.C.url, Version(1,2,3)...v126), (MockProject.E.url, v2...v2))
                    case .C: return MockCheckout(.C, [v126], (MockProject.D.url, v2...v2), (MockProject.E.url, v1..<Version(2,1,0)))
                    case .D: return MockCheckout(.D, [v2], (MockProject.F.url, v1..<v2))
                    case .E: return MockCheckout(.E, [v2], (MockProject.F.url, v1...v1))
                    case .F: return MockCheckout(.F, [v1])
                }
            }
        }

        let rv: [MockCheckout] = try! MyMockFetcher().recursivelyFetch([
            (MockProject.A.url, v1...v1),
        ])

        XCTAssertEqual(rv, [
            MockCheckout(.F, v1),
            MockCheckout(.D, v2),
            MockCheckout(.E, v2),
            MockCheckout(.C, v126),
            MockCheckout(.B, v2),
            MockCheckout(.A, v1)
        ])
    }

    func testVersionConstrain() {
        let r1 = Version(1,2,3)...Version(1,2,5)
        let r2 = Version(1,2,6)...Version(1,2,6)
        let r3 = Version(1,2,4)...Version(1,2,4)

        XCTAssertNil(r1.constrain(to: r2))
        XCTAssertNotNil(r1.constrain(to: r3))

        let r4 = Version(2,0,0)...Version(2,0,0)
        let r5 = Version(1,2,6)...Version(2,0,0)

        XCTAssertNotNil(r4.constrain(to: r5))

        let r6 = Version(1,2,3)...Version(1,2,3)
        XCTAssertEqual(r6.constrain(to: r6), r6)
    }

    func testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Simple() {
        class MyMockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                    case .A: return MockCheckout(.A, [v1], (MockProject.C.url, Version(1,2,3)..<v2))
                    case .B: return MockCheckout(.B, [v1], (MockProject.C.url, v2...v2))  // this is outside the above bounds
                    case .C: return MockCheckout(.C, ["1.2.3", "1.9.9", "2.0.1"])
                default:
                    fatalError()
                }
            }
        }

        var invalidGraph = false
        do {
            try MyMockFetcher().recursivelyFetch([
                (MockProject.A.url, Version.maxRange),
                (MockProject.B.url, Version.maxRange)
            ])
        } catch dep.Error.InvalidDependencyGraph(let url) {
            invalidGraph = true
            XCTAssertEqual(url, MockProject.C.url)
        } catch {
            XCTFail()
        }

        XCTAssertTrue(invalidGraph)
    }

    func testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Complex() {

        class MyMockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                switch MockProject(rawValue: url)! {
                    case .A: return MockCheckout(.A, [v1], (MockProject.C.url, Version(1,2,3)..<v2), (MockProject.D.url, v126...v2), (MockProject.B.url, v1...v2))
                    case .B: return MockCheckout(.B, [v2], (MockProject.C.url, Version(1,2,3)...v126), (MockProject.E.url, v2...v2))
                    case .C: return MockCheckout(.C, ["1.2.4"], (MockProject.D.url, v2...v2), (MockProject.E.url, v1..<Version(2,1,0)))
                    case .D: return MockCheckout(.D, [v2], (MockProject.F.url, v1..<v2))
                    case .E: return MockCheckout(.E, ["2.0.1"], (MockProject.F.url, v2...v2))
                    case .F: return MockCheckout(.F, [v2])
                }
            }
        }

        var invalidGraph = false
        do {
            try MyMockFetcher().recursivelyFetch([
                (MockProject.A.url, v1...v1),
            ])
        } catch Error.InvalidDependencyGraph(let url) {
            XCTAssertEqual(url, MockProject.F.url)
            invalidGraph = true
        } catch {
            XCTFail()
        }
        XCTAssertTrue(invalidGraph)
    }

    func testVersionUnavailable() {
        class MyMockFetcher: _MockFetcher {
            override func fetch(url url: String) throws -> Fetchable {
                return MockCheckout(.A, [v2])
            }
        }

        var success = false
        do {
            try MyMockFetcher().recursivelyFetch([(MockProject.A.url, v1..<v2)])
        } catch Error.InvalidDependencyGraph {
            success = true
        } catch {
            XCTFail()
        }
        XCTAssertTrue(success)
    }
//
//    func testGetRequiresUpdateToAlreadyInstalledPackage() {
//        class MyMockFetcher: MockFetcher {
//            override func specsForCheckout(checkout: MockCheckout) -> [(String, Range<Version>)] {
//                switch checkout.project {
//                case .A: return [(MockProject.C.url, Version(1,2,3)..<v2), (MockProject.D.url, v126...v2), (MockProject.B.url, v1...v2)]
//                case .B: return [(MockProject.C.url, Version(1,2,3)...v126), (MockProject.E.url, v2...v2)]
//                case .C: return [(MockProject.D.url, v2...v2), (MockProject.E.url, v1..<Version(2,1,0))]
//                case .D: return [(MockProject.F.url, v1..<v2)]
//                case .E: return [(MockProject.F.url, v2...v2)]
//                case .F: return []
//                }
//            }
//        }
//
//    }
}


///////////////////////////////////////////////////////////////// private

private let v1 = Version(1,0,0)
private let v2 = Version(2,0,0)
private let v123 = Version(1,2,3)
private let v126 = Version(1,2,6)
private let v199 = Version(1,9,9)

private enum MockProject: String {
    case A
    case B
    case C
    case D
    case E
    case F
    var url: String { return rawValue }
}

private class MockCheckout: Equatable, CustomStringConvertible, Fetchable {
    let project: MockProject
    let dependencies: [(String, Range<Version>)]
    var availableVersions: [Version]
    var _version: Version?

    init(_ project: MockProject, _ availableVersions: [Version], _ dependencies: (String, Range<Version>)...) {
        self.availableVersions = availableVersions
        self.project = project
        self.dependencies = dependencies
    }

    init(_ project: MockProject, _ version: Version) {
        self._version = version
        self.project = project
        self.dependencies = []
        self.availableVersions = []
    }

    var description: String { return "\(project)\(version)" }

    func constrain(to versionRange: Range<Version>) -> Version? {
        return availableVersions.filter{ versionRange ~= $0 }.last
    }

    var version: Version {
        return _version!
    }

    func setVersion(newValue: Version) throws {
        _version = newValue
    }
}

private func ==(lhs: MockCheckout, rhs: MockCheckout) -> Bool {
    return lhs.project == rhs.project && lhs.version == rhs.version
}

private class _MockFetcher: Fetcher {
    private typealias T = MockCheckout

    func find(url url: String) throws -> Fetchable? {
        return nil
    }

    func finalize(fetchable: Fetchable) throws -> MockCheckout {
        return fetchable as! T
    }

    func fetch(url url: String) throws -> Fetchable {
        fatalError("This must be implemented in each test")
    }
}
