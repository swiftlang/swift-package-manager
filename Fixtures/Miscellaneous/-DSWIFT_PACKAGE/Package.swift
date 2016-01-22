import PackageDescription

#if SWIFT_PACKAGE
let package = Package(name: "PackageManagerIsDefined")
#else
let package = Package(name: "PackageManagerIsNotDefined")
#endif
