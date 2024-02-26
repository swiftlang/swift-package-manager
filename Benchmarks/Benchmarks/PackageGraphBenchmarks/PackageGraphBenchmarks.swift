import Basics
import Benchmark
import PackageModel
import Workspace

let benchmarks = {
    Benchmark(
        "Package graph loading",
        configuration: .init(
            metrics: BenchmarkMetric.all,
            maxDuration: .seconds(10)
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
