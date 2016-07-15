import PackageDescription

let package = Package(
    name: "Case2",
    exclude: ["InvalidSource1.swift", "Sources/InvalidSource2.swift"]
)
