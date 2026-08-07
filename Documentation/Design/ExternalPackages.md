# External Packages

One of the themes we’ve been trying to address this year is how the package and build system can better support Swift’s powerful language interoperability. There is a rich collection of C and C++ libraries that would help Swift developers get a start on their projects. The effort to create packages that provide Swift bindings for these libraries are currently cumbersome to create and hard to maintain as the underlying packages update their APIs.

This proposal aims to give SwiftPM the tools it needs to help with creating these bridging packages. We add the ability to express dependencies on these libraries and manage them as we do with Swift package dependencies. The libraries can be provided in either source or binary form or both. When provided in source form, we add a new SwiftPM plugin capability to be able to invoke the build system that library uses to produce the necessary binaries. We then add the concept of an external library target that integrates the binaries. If the dependency is a binary distribution, SwiftPM will fetch the archive and extract it in the scratch directory.

Finally, to organize all this we add the concept of an external package which provides a package manifest for the dependency which will hold the plugin usage for the external builder and the target definitions for the dependencies build artifacts. Ideally all such external libraries adopt package manifests, but this gives the opportunity to provide one for them without having to wait.

## An Example

To help illustrate these concepts, we use the popular SDL (Simple DirectMedia Layer) library that provides a cross-platform API to manage low level access to the hardware necessary to make multimedia applications and games. This is an example of how this library can be integrated into a Swift package that will provide Swift bindings for this library.

```
// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "swift-sdl",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "SwiftSDL3",
            targets: ["SwiftSDL3"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.5.0"),
        .externalSource(url: "https://github.com/libsdl-org/SDL", from: "3.4.14"),
    ],
    externals: [
        Package(
            name: "SDL",
            products: [
                .library(name: "SDL3", type: .static, targets: ["SDL3"]),
            ],
            targets: [
                .externalLibrary(
                    name: "SDL3",
                    cSettings: [
                        .publicHeaderPath("include"),
                    ],
                    linkerSettings: [
                        .linkedFramework("CoreMedia", .when(platforms: [.macOS])),
                        <etc>
                    ],
                    plugins: [
                        "CMakeBuilderPlugin"
                    ]
                ),
            ]
        ),
    ],
    targets: [
        .target(
            // The modulemap and Swift bindings for SDL3
            name: "SwiftSDL3",
            dependencies: [
                .product(name: "SDL3", package: "SDL"),
            ]
        ),
        .executableTarget(
        	// The executable that manages the CMake build for the external package
            name: "CMakeBuilder",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .plugin(
        	// The plugin script that hooks up the CMakeBuilder to the package
            name: "CMakeBuilderPlugin",
            capability: .externalBuilder,
            dependencies: ["CMakeBuilder"]
        ),
    ],
)
```

## External Source Packages

This package provides the Swift binding to SDL3 with the SwiftSDL3 module. To enable SwiftPM to build SDL3 from source, we add a dependency on its git repository. SwiftPM will use it’s package resolution algorithms to select the desired version for the library. In this example it will resolve to the latest minor version equal or greater than version 3.4.14 as per semantic versioning. If SDL doesn’t follow SerVer, a more precise range can be provided.

```
        .externalSource(url: "https://github.com/libsdl-org/SDL", from: "3.4.14"),
```

Next the package provides the package description that will be applied to the SDL source tree in its `externals` list. This description is the same as any package and inherits the power of packages. It essentially enables SwiftPM to treat the external dependency as any other package. Note though that the name of the package has to match the package identity in the dependency, in this case “SDL”.

```
    externals: [
        Package(
            name: "SDL",
```

In order to build the package and produce the static library that will be incorporated into the binding target, we create a new plugin capability, `externalBuilder`. External builders are applied at the package level. The plugin creates a Command for the builder passing it the plugin output directory where it should place the build results. In this example we use SDL’s CMake build system. The builder would detect when the invoke CMake’s configure step and then invoke CMake’s build step. The builder runs on every invocation of swift build so needs to manage incremental builds to ensure duplicate work doesn’t happen. CMake’s build step does that automatically.

To properly build the static library to match the build request for the Swift package, the builder is passed a number of build parameters in it’s environment. For Swift Build builds, these map to macro expressions for the current build though the environment variables are intentionally named to be more generic to allow future build systems to be integrated in SwiftPM. The current set include:

- `SWIFT_CONFIGURATION` the current build configuration, e.g. Debug or Release
- `SWIFT_PLATFORM` the name of the platform
- `SWIFT_ARCHS` the list of cpu architectures to build for
- `SWIFT_VENDOR` the vendor component of the triple
- `SWIFT_OS` the os component of the triple
- `SWIFT_SUFFIX` the suffix component of the triple
- `SWIFT_SDK` the path to the SDK use for this build

The plugin output directory is independent of the build request. Since multiple request may come in for different platform configurations, the builder needs to make sure it produces the build output in a platform configuration specific directory to avoid collisions.

To integrate the libraries from the external package into the package graph, we introduce a new target type, `externalLibrary`. This target maps to a static or dynamic library as specified by the matching product. The path for the target is the relative path of the library from the build output directory. Build settings can be provided which consuming targets will apply when using the library. We introduce a new setting for `publicHeaderPath` which for external libraries is the relative path from the package root of any directories to add to the include path. Finally the target specifies the external build plugin that is used to create the library. If multiple libraries are provided by the given external builder, they specify the same plugin. The plugin is attached to the package, not the target. This also means multiple external builders may be used though that is usually unnecessary.

External packages may also specify executable targets that are produced by the external builder. These may be code generators or other tools and can be integrated into the package build including as tools for other build tool plugins.

## Future Work

### Archive Dependencies

Currently SwiftPM supports dependencies based on a local path, a git repository, or a package registry. For a number of source repositories and for the binary dependency case mentioned next, we will add the ability to specify a dependency on a remote archive file. This would specify the URL and checksum for the archive file. SwiftPM would then download it to the cache, check the checksum, and if successful extract it to the scratch path and used as the package root for the package.

This is not specifically for external packages and can be used for regular Swift packages as well. This could be used to speed up package resolution times when the dependency is on a specific version of the package.

### External Binary Packages

This proposal discusses external source package specifically. However library providers often provide prebuilt distributions of the library for a collection of platforms. We will add an additional dependency type for these binary distributions. An external package is defined to declare the contents of the binary distribution. These packages may use archive dependencies as mentioned above or may point to a relative local file path to the extracted archive.

To properly bring the binaries into the package manifest, we will need to make sure we can properly apply platform conditionals on those targets. This would include the SDK and the CPU architecture they support. And for binary packages providing Swift modules not build with library evolution, we need to be able to specify the compiler version it supports.

Binary packages become the recommended way of integrating binary artifacts. Binary targets have proven to be cumbersome outside their natural capability around xcframeworks. They require package providers or consumers to create and distribute a new SwiftPM specific artifact bundle archive for the binaries where binary packages allow consumers to point at existing binary distributions. It also allows consumers to specify and add dependencies on the libraries and executables available directly in the package graph.

Traditionally, SwiftPM has downloaded binary target bundles and prebuilts during package resolution time. To ensure it’s not downloading more than we need, it might make more sense to add the download step in as a prebuild step in the build so that it can download only what it needs.