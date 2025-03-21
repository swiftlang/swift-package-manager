# How to use Environment-Dependent Shared Libraries

An Environment-Dependent Shared Library (EDSL) is a shared library that is built for a specific environment and can be upgraded without recompiling executables that depend on it.

EDSLs bake in a number of assumptions, such as:

- The target Operating System
- The target CPU architecture
- The version of the installed libc and libstdc++ system libraries
- The version of the Swift compiler used to build the library and its clients
- The version of the installed Swift runtime
- The location of the installed Swift runtime

Therefore, they are generally intended for internal distribution, often across a fleet of identically-configured servers.

This article will demonstrate how to create a simple EDSL called `libKrabbyPatty` and use it in a client application called `KrustyKrab`, all using SwiftPM.

## Creating the EDSL

Begin by setting up a standard SwiftPM project layout, containing a single module named `KrabbyPatty`.

```
📂 swift-krabby-patty
├── 📂 Sources
│   └── 📂 KrabbyPatty
│       └── 📜 KrabbyPatty.swift
└── 📜 Package.swift
```

In `KrabbyPatty.swift`, add an enum named `KrabbyPattyFormula` with a single case `v1`. Add a static property `latest` that returns `v1`.

```swift
public
enum KrabbyPattyFormula
{
    case v1

    public
    static var latest:Self { .v1 }
}
```

In `Package.swift`, add a target description for the `KrabbyPatty` module, and make sure to enable library evolution using the `-enable-library-evolution` flag. This prevents the Swift compiler from making unsafe assumptions about the code in the library in case it is modified in the future, which is what we intend to do.

Finally, add a product description for the `KrabbyPatty` library, with the linkage type set to `dynamic`.

```swift
// swift-tools-version:6.0
import PackageDescription

let package:Package = .init(name: "swift-krabby-patty",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .visionOS(.v2), .watchOS(.v11)],
    products: [
        .library(name: "KrabbyPatty", type: .dynamic, targets: ["KrabbyPatty"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "KrabbyPatty",
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"]),
            ]),
    ]
)
```

## Packaging the EDSL

The `libKrabbyPatty` binary may be built simply by running `swift build`.

```bash
swift build -c release --product KrabbyPatty
```

To allow other projects to consume the library, you must create an `artifactbundle` directory with the following layout:

```
📂 main.artifactbundle
    📂 KrabbyPatty
        ⚙️ libKrabbyPatty.so
        📜 KrabbyPatty.swiftinterface
    📜 info.json
```

Note that on macOS, the library would have a `dylib` extension instead of an `so` extension.

```bash
mkdir -p main.artifactbundle/KrabbyPatty
cp .build/release/Modules/KrabbyPatty.swiftinterface main.artifactbundle/KrabbyPatty
cp .build/release/libKrabbyPatty.so main.artifactbundle/KrabbyPatty

(
cat <<EOF
{
    "schemaVersion": "1.2",
    "artifacts": {
        "KrabbyPatty": {
            "type": "library",
            "version": "1.0.0",
            "variants": [{ "path": "KrabbyPatty" }]
        }
    }
}
EOF
) > main.artifactbundle/info.json
```

Although `variants` is an array, an EDSL bundle must contain exactly one path per library. In this example, we named the directory `KrabbyPatty` to match the name of the library, but you could choose any name you like.

You should now have a layout similar to the following:

```
📂 swift-krabby-patty
├── 📂 main.artifactbundle
│   ├── 📂 KrabbyPatty
│   └── 📜 info.json
├── 📂 Sources
│   └── 📂 KrabbyPatty
│       └── 📜 KrabbyPatty.swift
└── 📜 Package.swift
```

## Consuming the EDSL

Create a new SwiftPM project named `swift-krusty-krab` alongside the `swift-krabby-patty` project. The `swift-krusty-krab` project should contain a source directory for a module named `KrustyKrab`.

```
📂 swift-krabby-patty
├── 📂 main.artifactbundle
├── 📂 Sources
└── 📜 Package.swift

📂 swift-krusty-krab
├── 📂 Sources
│   └── 📂 KrustyKrab
│       └── 📜 Main.swift
└── 📜 Package.swift
```

In `Main.swift`, import the `KrabbyPatty` module and print the latest `KrabbyPattyFormula` version.

```swift
import KrabbyPatty

print("Latest Krabby Patty formula version: \(KrabbyPattyFormula.latest)")
```

In `Package.swift`, add a binary target description for the `KrabbyPatty` library, and point it to the `main.artifactbundle` directory in the sibling project. Then add an executable target description for `KrustyKrab` itself, and make it depend on the `KrabbyPatty` target.

```swift
// swift-tools-version:6.0
import PackageDescription

let package:Package = .init(name: "swift-krusty-krab",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .visionOS(.v2), .watchOS(.v11)],
    products: [
        .executable(name: "KrustyKrab", targets: ["KrustyKrab"]),
    ],
    dependencies: [
    ],
    targets: [
        .binaryTarget(
            name: "KrabbyPatty",
            path: "../swift-krabby-patty/main.artifactbundle"),

        .executableTarget(name: "KrustyKrab",
            dependencies: [
                .target(name: "KrabbyPatty"),
            ]),
    ]
)
```

If you then run the `KrustyKrab` executable, you should see the following output:

```bash
swift run KrustyKrab
```

```
Latest Krabby Patty formula version: v1
```

## Redeploying the EDSL

To get the most out of an EDSL, you should compile the client application with an `@rpath` that allows you to upgrade the library later without recompiling the client.

The command below builds the `KrustyKrab` executable against version 1.0.0 of `libKrabbyPatty`, and embeds an `@rpath` that points to some directory named `Libraries`.

```bash
swift build -c release --product KrustyKrab \
    -Xlinker -rpath \
    -Xlinker Libraries
```

If we run the executable now, we should still see the same output as before, because SwiftPM copies the `libKrabbyPatty` binary that it was built against into the `.build` directory, and `KrustyKrab` uses that copy.

```bash
.build/release/KrustyKrab
```

```
Latest Krabby Patty formula version: v1
```

Now, let’s change the `KrabbyPattyFormula` enum in the `KrabbyPatty` module to include a new case `v2`, and update the `latest` property to return `v2`.

```diff
public
enum KrabbyPattyFormula
{
    case v1
+   case v2

    public
-   static var latest:Self { .v1 }
+   static var latest:Self { .v2 }
}
```

Build the library once more, create the expected `Libraries` directory, and copy the new version of the library into it.

```bash
cd ../swift-krabby-patty
swift build -c release --product KrabbyPatty
cd ../swift-krusty-krab
mkdir Libraries
cp ../swift-krabby-patty/.build/release/libKrabbyPatty.so Libraries
```

If you re-run the `KrustyKrab` executable, you should still see the output from the previous version of the library, because the executable prefers the library in the `.build` directory over the one in the `Libraries` directory.

```bash
.build/release/KrustyKrab
```

```
Latest Krabby Patty formula version: v1
```

However, if you delete the copy of the library in the `.build` directory, the executable will use the library in the `Libraries` directory, and you should see the new output.

```bash
rm .build/release/libKrabbyPatty.so
.build/release/KrustyKrab
```

```
Latest Krabby Patty formula version: v2
```
