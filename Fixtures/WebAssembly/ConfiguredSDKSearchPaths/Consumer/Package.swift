// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "GreeterUser",
    targets: [
        .executableTarget(
            name: "GreeterUser",
            linkerSettings: [
                // `Greeter` is not declared as a target dependency; its module and static archive
                // are resolved through the SDK's include/library search paths (populated via
                // `swift sdk configure` in the enclosing test).
                .linkedLibrary("Greeter"),
            ]
        ),
    ]
)
