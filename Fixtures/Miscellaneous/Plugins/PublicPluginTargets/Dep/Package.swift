// swift-tools-version: 999.0
import PackageDescription

// Dep declares no products; its command plugins are exposed through target visibility instead.
let package = Package(
    name: "Dep",
    targets: [
        .target(name: "DepLib", visibility: .public),
        .plugin(
            name: "PublicCmd",
            capability: .command(
                intent: .custom(verb: "public-cmd", description: "A command plugin with public visibility")
            ),
            visibility: .public
        ),
        .plugin(
            name: "PackageCmd",
            capability: .command(
                intent: .custom(verb: "package-cmd", description: "A command plugin with package visibility")
            )
        ),
    ]
)
