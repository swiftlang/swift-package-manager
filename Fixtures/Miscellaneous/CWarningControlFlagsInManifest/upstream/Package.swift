// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "upstream",
    products: [
        .library(name: "CUpstream", targets: ["CUpstream"]),
    ],
    targets: [
        .target(
            name: "CUpstream",
            // Declare the SE-0480 warning-control settings for the C compiler in the
            // manifest. `treatAllWarnings` lowers to `-Werror` and `treatWarning`
            // lowers to `-Werror=<name>` in OTHER_CFLAGS.
            cSettings: [
                .treatAllWarnings(as: .error),
                .treatWarning("return-type", as: .error),
            ]
        ),
    ]
)
