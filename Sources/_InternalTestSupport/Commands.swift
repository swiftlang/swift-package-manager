import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration
import XCTest

open class BuildSystemProviderTestCase: XCTestCase {
    open var buildSystemProvider: BuildSystemProvider.Kind {
        fatalError("\(self) does not implement \(#function)")
    }
}

open class BuildConfigurationTestCase: BuildSystemProviderTestCase {
    open var binPathSuffixes: [String] {
        fatalError("\(self) does not implement \(#function)")
    }

    open var buildConfig: BuildConfiguration {
        fatalError("\(self) does not implement \(#function)")
    }

}
