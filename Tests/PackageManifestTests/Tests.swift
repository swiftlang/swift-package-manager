import Basics
import PackageManifest
import XCTest

final class PackageManifestTests: XCTestCase {

    func test0() throws {
        let package = Package()
            .minimumDeploymentTarget {
                MacOS("10.15")
                iOS("12.0")
            }
            .modules {
                Executable("module-executable")
                    .include {
                        Internal("module-library", public: true)
                        Internal("module-library-2")
                    }
                Library("module-library", public: true)
                    .customPath("custom/path")
                    .exclude("exclude")
                    .swiftSettings("swiftSettings")
                    .cxxSettings("cxxSettings")
                    .include {
                        External("foo", from: "remote-major-1")
                        External("bar", from: "remote-major-2")
                    }
                Library("module-library-2")
                Test("module-test", for: "module-library")
                    .sources("sources-1", "sources-2")
                    .exclude("exclude-1", "exclude-2")
                    .swiftSettings("swiftSettings-1", "swiftSettings-2")
                    .cxxSettings("cxxSettings-1", "cxxSettings-2")
                Plugin("module-plugin", capability: .buildTool, public: true)
                    .customPath("custom/path")
                Binary("module-binary", url: "url", checksum: "checksum")
                System("system")
                    .providers {
                        apt("apt-1", "apt-2")
                        yum("yum-1", "yum-2")
                        yum("yum-3")
                        brew("brew")
                    }
            }
            .dependencies {
                FileSystem(at: "/tmp/foo")
                SourceControl(at: "http://localhost/remote-major-1", upToNextMajor: "1.0.0")
                SourceControl(at: "http://localhost/remote-major-2", upToNextMajor: "2.0.0")
                SourceControl(at: "/tmp/local-branch", branch: "main")
                Registry(identity: "foo/bar", exact: "1.0.5")
                Registry(identity: "foo/baz", upToNextMajor: "3.0.0")
            }


        // *******

        let encoder = JSONEncoder.makeWithDefaults()
        try print(String(data: encoder.encode(package), encoding: .utf8)!)
    }

    func test1() throws {
        let package = Package()
            .modules {
                Library("module-standard")
                    .include {
                        External("foo", from: "remote-major-1")
                        External("bar", from: "remote-major-2")
                    }
                if ProcessInfo.processInfo.environment["condition"] == "true" {
                    Test("module-test", for: "module-standard")
                }
                Plugin("module-plugin", capability: .buildTool, public: true)
                #if os(macOS)
                Binary("module-binary", url: "url", checksum: "checksum")
                #endif
            }
            .dependencies {
                FileSystem(at: "/tmp/foo")
                if ProcessInfo.processInfo.environment["condition"] == "true" {
                    SourceControl(at: "http://localhost/remote-major-1", upToNextMajor: "1.0.0")
                } else {
                    SourceControl(at: "http://localhost/remote-major-2", upToNextMajor: "2.0.0")
                }
                SourceControl(at: "/tmp/local-branch", branch: "main")
            }


        // *******

        let encoder = JSONEncoder.makeWithDefaults()
        try print(String(data: encoder.encode(package), encoding: .utf8)!)
    }

    func test2() throws {
        let package = Package()

        package.modules.append(.library(name: "my-lib-1"))

        var librarySettings = Module.LibrarySettings()
        librarySettings.dependencies.append(ModuleDependency.external(name: "NIO", packageIdentity: "swift-nio"))
        librarySettings.swiftSettings = ["swiftSettings"]
        var library = Module.library(name: "my-lib-2", settings: librarySettings)
        library.customPath = "/some-path"
        package.modules.append(library)

        var executableSettings = Module.ExecutableSettings()
        executableSettings.sources = ["file1.swift"]
        executableSettings.dependencies.append(.init(library))
        let executable = Module.executable(name: "my-exec", settings: executableSettings)
        package.modules.append(executable)

        package.dependencies.append(.fileSystem(.init(path: "/tmp/foo")))
        package.dependencies.append(.sourceControl(.init(location: "http://localhost/swift-nio", requirement: .range("1.0.0" ..< "2.0.0"))))

        package.minimumDeploymentTargets.append(DeploymentTarget(platform: .macOS, version: "12.0"))

        // *******

        let encoder = JSONEncoder.makeWithDefaults()
        try print(String(data: encoder.encode(package), encoding: .utf8)!)
    }

    func test3() throws {
        let library1 = Library("library1")
            .include {
                External("foo", from: "dependency1")
                External("bar", from: "dependency2")
            }

        let library2 = Library("library2")

        let package = Package()
            .modules {
                library1
                library2
                Executable("executable1")
                    .include {
                        library1
                        (library2, public: true)
                    }
                Executable("executable2")
                    .include {
                        library1.name
                        Internal(library2.name)
                    }
                Test("library-test", for: library1)
                Test("library2-test", for: library2)
            }
            .dependencies {
                SourceControl(at: "http://localhost/dependency1", upToNextMajor: "1.0.0")
                SourceControl(at: "http://localhost/dependency2", upToNextMajor: "1.0.0")
            }

        // *******

        let encoder = JSONEncoder.makeWithDefaults()
        try print(String(data: encoder.encode(package), encoding: .utf8)!)
    }
}
