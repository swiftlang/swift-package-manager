// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "LibraryEvolution",
    products: [
    ],
    targets: [
        .target(name: "A", dependencies: [], swiftSettings: [.unsafeFlags(["-enable-library-evolution"])]),
        .target(name: "B", dependencies: ["A"], swiftSettings: [.unsafeFlags(["-enable-library-evolution"])]),
    ])
