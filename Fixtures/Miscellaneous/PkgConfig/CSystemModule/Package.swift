// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "CSystemModule",
    pkgConfig: "libSystemModule",
    providers: [
        .brew(["SystemModule"]),
    ]
)

