import Workspace

let swiftpm = SwiftPMHelper(rootPackage: localFileSystem.currentWorkingDirectory!)
let workspace = swiftpm.createWorkspace()

let diagnostics = DiagnosticsEngine()
let packageGraph = workspace.loadPackageGraph(root: swiftpm.rootPackage, diagnostics: diagnostics)

let numberOfFiles = packageGraph.allTargets.reduce(0, { $0 + $1.sources.paths.count })
print("Number of source files:", numberOfFiles)

let rootPackageTargets = packageGraph.rootPackages.flatMap({ $0.targets }).map({ $0.name }).joined(separator: ", ")
print("Targets:", rootPackageTargets)

let products = packageGraph.allProducts.map({ $0.name }).joined(separator: ", ")
print("Products:", products)
