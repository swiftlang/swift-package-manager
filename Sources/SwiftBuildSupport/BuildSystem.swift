import SPMBuildCore
import PackageModel

extension BuildConfiguration {
    public var swiftbuildName: String {
        switch self {
        case .debug: "Debug"
        case .release: "Release"
        }
    }
}

extension BuildSubset {
    var pifTargetName: String {
        switch self {
        case .product(let name, _):
            targetName(forProductName: name)
        case .target(let name, _):
            name
        case .allExcludingTests:
            PIFBuilder.allExcludingTestsTargetName
        case .allIncludingTests:
            PIFBuilder.allIncludingTestsTargetName
        }
    }
}
