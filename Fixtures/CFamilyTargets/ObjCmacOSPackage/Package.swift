// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "ObjCmacOSPackage",
    targets: [
        .target(name: "ObjCmacOSPackage", path: "Sources"),
        .testTarget(name: "ObjCmacOSPackageTests", dependencies: ["ObjCmacOSPackage"]),
    ]
)
