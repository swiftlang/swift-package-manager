// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "PluginsAndSnippets",
    products: [
        .plugin(
            name: "PluginScriptProduct",
            targets: [
                "PluginScriptTarget"
            ]
        ),
    ],
    targets: [
        .plugin(
            name: "PluginScriptTarget",
            capability: .command(
                intent: .custom(
                    verb: "do-something",
                    description: "Do something"
                )
            )
        ),
    ]
)
