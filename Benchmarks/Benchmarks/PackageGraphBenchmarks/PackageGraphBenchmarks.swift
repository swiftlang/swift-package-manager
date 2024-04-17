@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import Basics
import Benchmark
import Foundation
import PackageModel

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import func PackageGraph.loadModulesGraph

import class TSCBasic.InMemoryFileSystem
import Workspace

let benchmarks = {
    let defaultMetrics: [BenchmarkMetric]
    if let envVar = ProcessInfo.processInfo.environment["SWIFTPM_BENCHMARK_ALL_METRICS"],
    envVar.lowercased() == "true" || envVar == "1" {
        defaultMetrics = .all
    } else {
        defaultMetrics = [
            .mallocCountTotal,
            .syscalls,
        ]
    }

    let modulesGraphDepth: Int
    if let envVar = ProcessInfo.processInfo.environment["SWIFTPM_BENCHMARK_MODULES_GRAPH_DEPTH"],
    let parsedValue = Int(envVar) {
        modulesGraphDepth = parsedValue
    } else {
        modulesGraphDepth = 100
    }

    let modulesGraphWidth: Int
    if let envVar = ProcessInfo.processInfo.environment["SWIFTPM_BENCHMARK_MODULES_GRAPH_WIDTH"],
    let parsedValue = Int(envVar) {
        modulesGraphWidth = parsedValue
    } else {
        modulesGraphWidth = 100
    }

    let packagesGraphDepth: Int
    if let envVar = ProcessInfo.processInfo.environment["SWIFTPM_BENCHMARK_PACKAGES_GRAPH_DEPTH"],
    let parsedValue = Int(envVar) {
        packagesGraphDepth = parsedValue
    } else {
        packagesGraphDepth = 10
    }

    let noopObservability = ObservabilitySystem.NOOP

    // Benchmarks computation of a resolved graph of modules for a package using `Workspace` as an entry point. It runs PubGrub to get
    // resolved concrete versions of dependencies, assigning all modules and products to each other as corresponding dependencies
    // with their build triples, but with the build plan not yet constructed. In this benchmark specifically we're loading `Package.swift`
    // for SwiftPM itself.
    Benchmark(
        "SwiftPMWorkspaceModulesGraph",
        configuration: .init(
            metrics: defaultMetrics,
            maxDuration: .seconds(10),
            thresholds: [
                .mallocCountTotal: .init(absolute: [.p90: 12000]),
                .syscalls: .init(absolute: [.p90: 1600]),
            ]
        )
    ) { benchmark in
        let path = try AbsolutePath(validating: #file).parentDirectory.parentDirectory.parentDirectory
        let workspace = try Workspace(fileSystem: localFileSystem, location: .init(forRootPackage: path, fileSystem: localFileSystem))

        for _ in benchmark.scaledIterations {
            try workspace.loadPackageGraph(rootPath: path, observabilityScope: noopObservability)
        }
    }


    // Benchmarks computation of a resolved graph of modules for a synthesized package using `loadModulesGraph` as an
    // entry point, which almost immediately delegates to `ModulesGraph.load` under the hood.
    Benchmark(
        "SyntheticModulesGraph",
        configuration: .init(
            metrics: defaultMetrics,
            maxDuration: .seconds(10),
            thresholds: [
                .mallocCountTotal: .init(absolute: [.p90: 2500]),
                .syscalls: .init(absolute: [.p90: 0]),
            ]
        )
    ) { benchmark in
        let targets = try (0..<modulesGraphWidth).map { i in
            try TargetDescription(name: "Target\(i)", dependencies: (0..<min(i, modulesGraphDepth)).map {
                .target(name: "Target\($0)")
            })
        }
        let fileSystem = InMemoryFileSystem(
            emptyFiles: targets.map { "/benchmark/Sources/\($0.name)/empty.swift" }
        )
        let rootPackagePath = try AbsolutePath(validating: "/benchmark")

        let manifest = Manifest(
            displayName: "benchmark",
            path: rootPackagePath,
            packageKind: .root(rootPackagePath),
            packageLocation: rootPackagePath.pathString,
            defaultLocalization: nil,
            platforms: [],
            version: nil,
            revision: nil,
            toolsVersion: .v5_10,
            pkgConfig: nil,
            providers: nil,
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )

        for _ in benchmark.scaledIterations {
            try blackHole(
                loadModulesGraph(fileSystem: fileSystem, manifests: [manifest], observabilityScope: noopObservability)
            )
        }
    }
}
