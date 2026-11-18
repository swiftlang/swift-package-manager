//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Basics
import PackageGraph
import PackageModel
import Testing

/// `Root` depends on `B` and `M`, and `M` depends on `B`. `M` asks for a trait of `B` that `Root`
/// doesn't, and that trait guards `B`'s dependency on `C`. Resolution has to fetch `C` however each
/// parent requires `B`, in either order, and whether or not `M` uses `B`.
struct TraitRequestResolutionTests {
    enum Requirement: String, CaseIterable, Sendable {
        case path, branch, version

        func dependency(on name: String, traits: Set<PackageDependency.Trait> = ["default"]) -> MockDependency {
            switch self {
            case .path:
                .fileSystem(path: "./\(name)", traits: traits)
            case .branch:
                .sourceControl(path: "./\(name)", requirement: .branch("main"), traits: traits)
            case .version:
                .sourceControl(path: "./\(name)", requirement: .upToNextMajor(from: "1.0.0"), traits: traits)
            }
        }

        /// Whether a package required this way is allowed to require a dependency that way.
        func allows(_ dependency: Requirement) -> Bool {
            switch self {
            case .path: true
            case .branch: dependency != .path
            case .version: dependency == .version
            }
        }
    }

    enum Usage: String, CaseIterable, Sendable {
        case used, unused, usedBehindDisabledTrait
    }

    enum Trigger: String, CaseIterable, Sendable {
        /// `B`'s trait `T` guards `C`; `M` names `T` and `Root` asks for defaults.
        case namedTrait
        /// `B`'s default trait `D` guards `C`; `Root` disables defaults and `M` asks for them.
        case defaultTrait

        var guardingTrait: String {
            switch self {
            case .namedTrait: "T"
            case .defaultTrait: "D"
            }
        }
    }

    struct Scenario: Sendable, CustomTestStringConvertible {
        let trigger: Trigger
        let rootToB: Requirement?
        let rootToM: Requirement
        let mToB: Requirement
        let usage: Usage
        let mFirst: Bool

        var testDescription: String {
            let order = self.rootToB == nil ? "" : self.mFirst ? ", M first" : ", B first"
            return "\(self.trigger): root→B \(self.rootToB?.rawValue ?? "none"), root→M \(self.rootToM), M→B \(self.mToB), M \(self.usage)\(order)"
        }

        static let all: [Scenario] = Trigger.allCases.flatMap { trigger in
            let usages: [Usage] = trigger == .namedTrait ? Usage.allCases : [.used]
            return usages.flatMap { usage in
                ([nil] + Requirement.allCases).flatMap { rootToB in
                    Requirement.allCases.flatMap { rootToM in
                        Requirement.allCases.filter(rootToM.allows).flatMap { mToB in
                            (rootToB == nil ? [false] : [false, true]).map { mFirst in
                                Scenario(
                                    trigger: trigger,
                                    rootToB: rootToB,
                                    rootToM: rootToM,
                                    mToB: mToB,
                                    usage: usage,
                                    mFirst: mFirst
                                )
                            }
                        }
                    }
                }
            }
        }

        func root() throws -> MockPackage {
            let m = self.rootToM.dependency(on: "M")
            let b = self.rootToB?.dependency(on: "B", traits: self.trigger == .defaultTrait ? [] : ["default"])
            let dependencies = [b, m].compactMap(\.self)
            return MockPackage(
                name: "Root",
                targets: [
                    try MockTarget(
                        name: "RootTarget",
                        dependencies: (self.rootToB == nil ? [] : [.product(name: "BProduct", package: "B")])
                            + [.product(name: "MProduct", package: "M")]
                    ),
                ],
                dependencies: self.mFirst ? dependencies.reversed() : dependencies
            )
        }

        func m() throws -> MockPackage {
            let usesB: TargetDescription.Dependency = .product(
                name: "BProduct",
                package: "B",
                condition: self.usage == .usedBehindDisabledTrait ? .init(traits: ["X"]) : nil
            )
            return MockPackage(
                name: "M",
                targets: [try MockTarget(name: "MTarget", dependencies: self.usage == .unused ? [] : [usesB])],
                products: [MockProduct(name: "MProduct", modules: ["MTarget"])],
                dependencies: [self.mToB.dependency(on: "B", traits: self.trigger == .namedTrait ? ["T"] : ["default"])],
                traits: self.usage == .usedBehindDisabledTrait ? ["X"] : [],
                versions: [nil, "main", "1.0.0"]
            )
        }

        var expectedPackages: [PackageIdentity] {
            self.rootToB == nil && self.usage != .used ? ["root", "m"] : ["root", "m", "b", "c"]
        }
    }

    @Test(arguments: Scenario.all)
    func resolvesTraitRequestedByEveryParent(_ scenario: Scenario) async throws {
        let workspace = try await MockWorkspace(
            sandbox: AbsolutePath("/tmp/ws/"),
            fileSystem: InMemoryFileSystem(),
            roots: [scenario.root()],
            packages: [
                scenario.m(),
                sharedPackage(
                    traits: scenario.trigger == .namedTrait ? ["T"] : [.init(name: "default", enabledTraits: ["D"]), "D"],
                    guardedBy: scenario.trigger.guardingTrait
                ),
                leafPackage(),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            expectNoDiagnostics(diagnostics)
            #expect(graph.packages.map(\.identity).sorted() == scenario.expectedPackages.sorted())
            if scenario.expectedPackages.contains("b") {
                #expect(graph.package(for: "b")?.enabledTraits == [scenario.trigger.guardingTrait])
            }
        }
    }

    /// The order dependence from the original report: `S` and `M` both depend on `B`, and only `M`
    /// names `T`.
    @Test(arguments: Requirement.allCases, Requirement.allCases)
    func resolvesTraitRequestedBySecondSibling(sToB: Requirement, mToB: Requirement) async throws {
        for mFirst in [false, true] {
            let siblings = [Requirement.path.dependency(on: "S"), Requirement.path.dependency(on: "M")]
            let workspace = try await MockWorkspace(
                sandbox: AbsolutePath("/tmp/ws/"),
                fileSystem: InMemoryFileSystem(),
                roots: [
                    MockPackage(
                        name: "Root",
                        targets: [
                            try MockTarget(
                                name: "RootTarget",
                                dependencies: [
                                    .product(name: "SProduct", package: "S"),
                                    .product(name: "MProduct", package: "M"),
                                ]
                            ),
                        ],
                        dependencies: mFirst ? siblings.reversed() : siblings
                    ),
                ],
                packages: [
                    try parentPackage(name: "S", dependency: sToB.dependency(on: "B")),
                    try parentPackage(name: "M", dependency: mToB.dependency(on: "B", traits: ["T"])),
                    try sharedPackage(traits: ["T"], guardedBy: "T"),
                    leafPackage(),
                ]
            )

            try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
                expectNoDiagnostics(diagnostics)
                #expect(graph.packages.map(\.identity).sorted() == ["b", "c", "m", "root", "s"], "M first: \(mFirst)")
                #expect(graph.package(for: "b")?.enabledTraits == ["T"], "M first: \(mFirst)")
            }
        }
    }

    /// `Root` asks for `M` without its trait `X` before `S` asks for it with `X`, and `X` is what
    /// makes `M` ask for `B`'s trait `T`.
    @Test
    func resolvesTraitEnabledThroughAnotherParentsTrait() async throws {
        let workspace = try await MockWorkspace(
            sandbox: AbsolutePath("/tmp/ws/"),
            fileSystem: InMemoryFileSystem(),
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        try MockTarget(
                            name: "RootTarget",
                            dependencies: [
                                .product(name: "MProduct", package: "M"),
                                .product(name: "SProduct", package: "S"),
                            ]
                        ),
                    ],
                    dependencies: [Requirement.path.dependency(on: "M"), Requirement.path.dependency(on: "S")]
                ),
            ],
            packages: [
                try parentPackage(name: "S", dependency: Requirement.path.dependency(on: "M", traits: ["X"]), using: "M"),
                MockPackage(
                    name: "M",
                    targets: [try MockTarget(name: "MTarget", dependencies: [.product(name: "BProduct", package: "B")])],
                    products: [MockProduct(name: "MProduct", modules: ["MTarget"])],
                    dependencies: [
                        Requirement.path.dependency(on: "B", traits: [.init(name: "T", condition: .init(traits: ["X"]))]),
                    ],
                    traits: ["X"],
                    versions: [nil, "main", "1.0.0"]
                ),
                try sharedPackage(traits: ["T"], guardedBy: "T"),
                leafPackage(),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            expectNoDiagnostics(diagnostics)
            #expect(graph.packages.map(\.identity).sorted() == ["b", "c", "m", "root", "s"])
            #expect(graph.package(for: "m")?.enabledTraits == ["X"])
            #expect(graph.package(for: "b")?.enabledTraits == ["T"])
        }
    }
}

private func sharedPackage(traits: Set<TraitDescription>, guardedBy trait: String) throws -> MockPackage {
    MockPackage(
        name: "B",
        targets: [
            try MockTarget(
                name: "BTarget",
                dependencies: [.product(name: "CProduct", package: "C", condition: .init(traits: [trait]))]
            ),
        ],
        products: [MockProduct(name: "BProduct", modules: ["BTarget"])],
        dependencies: [TraitRequestResolutionTests.Requirement.version.dependency(on: "C")],
        traits: traits,
        versions: [nil, "main", "1.0.0"]
    )
}

private func parentPackage(name: String, dependency: MockDependency, using package: String = "B") throws -> MockPackage {
    MockPackage(
        name: name,
        targets: [try MockTarget(name: "\(name)Target", dependencies: [.product(name: "\(package)Product", package: package)])],
        products: [MockProduct(name: "\(name)Product", modules: ["\(name)Target"])],
        dependencies: [dependency],
        versions: [nil, "main", "1.0.0"]
    )
}

private func leafPackage() throws -> MockPackage {
    MockPackage(
        name: "C",
        targets: [try MockTarget(name: "CTarget")],
        products: [MockProduct(name: "CProduct", modules: ["CTarget"])],
        versions: [nil, "1.0.0"]
    )
}
