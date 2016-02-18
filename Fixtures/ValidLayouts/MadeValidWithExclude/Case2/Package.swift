import PackageDescription

let package = Package(
    exclude: ["InvalidSource1.swift", "Sources/InvalidSource2.swift"]
)
