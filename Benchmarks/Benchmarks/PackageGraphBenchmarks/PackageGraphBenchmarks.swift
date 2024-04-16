import Basics
import Benchmark
import PackageModel
import Workspace

let benchmarks = {
    let defaultMetrics: [BenchmarkMetric] = [
        .mallocCountTotal,
        .syscalls,
    ]

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
        let system = ObservabilitySystem { _, _ in }

        for _ in benchmark.scaledIterations {
            try workspace.loadPackageGraph(rootPath: path, observabilityScope: system.topScope)
        }
    }
}
