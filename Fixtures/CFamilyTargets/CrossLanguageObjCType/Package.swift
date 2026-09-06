// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "CrossLanguageObjCType",
    targets: [
        .target(name: "TargetA"),
        .target(name: "TargetB", dependencies: ["TargetA"]),
        .target(name: "TargetC", dependencies: ["TargetB"]),
    ]
)
