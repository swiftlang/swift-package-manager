// swift-tools-version:5.4

import PackageDescription

let package = Package(
  name: "pkg",
  products: [
    .library(name: "pkg", targets: ["pkg"]),
  ],
  dependencies: [
    .package(path: "../dep"),
  ],
  targets: [
    .target(
      name: "pkg",
      dependencies: [.product(name: "Dep", package: "Dep")]),
  ]
)
