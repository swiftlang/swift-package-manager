// swift-tools-version: 999.0
import PackageDescription

// S16_MirrorsUpdate fixture: a workspace whose member depends on
// a bogus, unreachable URL. The test scaffolds a real local git
// repo at `external/some-lib` and sets a mirror redirecting the
// bogus URL to that local repo. `swift workspace update`
// only succeeds if the mirror was picked up from the workspace-
// root `mirrors.json` and consulted during resolution.
let workspace = Workspace(
    members: [
        "packages/app",
    ],
    dependencies: [
        .package(url: "https://example.invalid/some-lib.git", from: "1.0.0"),
    ],
)
