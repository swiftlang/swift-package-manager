// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PluginsAndSnippets",
    products: [
        .plugin(
            name: "PluginScriptProduct",
            targets: [
                "PluginScriptTarget"
            ],
        ),
        .library(
            name: "MyLib",
            targets: [
                "MyLib",
            ],
        ),
    ],
    targets: [
        .plugin(
            name: "PluginScriptTarget",
            capability: .command(
                intent: .custom(
                    verb: "do-something",
                    description: "Do something",
                ),
            ),
        ),
        .target(name: "MyLib"),
    ]
)
