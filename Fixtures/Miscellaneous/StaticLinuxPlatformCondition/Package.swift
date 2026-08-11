// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StaticLinuxPlatformCondition",
    targets: [
        .target(name: "LinuxDep"),
        .executableTarget(
            name: "tool",
            dependencies: [
                // This dependency is only active on Linux. When building with the static Linux
                // SDK (a `*-swift-linux-musl` triple) the `.linux` condition must remain active,
                // otherwise `LinuxDep` would be dropped and `import LinuxDep` in the executable
                // would fail to compile.
                .target(name: "LinuxDep", condition: .when(platforms: [.linux])),
            ]
        ),
    ]
)
