// swift-tools-version: 999.0
import PackageDescription

// S14_DumpPackage fixture: two workspace members with no external
// dependencies. `swift package dump-package` is a manifest-only
// command — it prints the parsed `Package.swift` of a single
// member as JSON. At a multi-member workspace root the caller
// must disambiguate via `--package <identity>`; from inside a
// member the CWD focus auto-selects.
let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
    ],
)
