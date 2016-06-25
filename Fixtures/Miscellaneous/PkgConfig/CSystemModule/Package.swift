import PackageDescription

let package = Package(
   name: "CSystemModule",
   pkgConfig: "libSystemModule",
   providers: [.Brew("SystemModule")]
)
