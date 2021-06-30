#if SERIALIZATION
#if canImport(Glibc)
@_implementationOnly import Glibc
#elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
@_implementationOnly import Darwin.C
#elseif os(Windows)
@_implementationOnly import ucrt
@_implementationOnly import struct WinSDK.HANDLE
#endif

// global state for serialization
var __packages = [Package]()
#endif

public class Package: Codable {
    public var modules: [Module]
    public var dependencies: [Dependency]
    public var minimumDeploymentTargets: [DeploymentTarget]

    public init() {
        self.modules = []
        self.dependencies = []
        self.minimumDeploymentTargets = []

        #if SERIALIZATION
        // register for serialization
        __packages.append(self)
        // FIXME: get rid of atexit in favor of more reliable solution
        atexit {
            if CommandLine.arguments.first?.contains("-manifest") ?? false {
                try! PackageSerializer.serialize(__packages.last!)
            }
        }
        #endif
    }
}
