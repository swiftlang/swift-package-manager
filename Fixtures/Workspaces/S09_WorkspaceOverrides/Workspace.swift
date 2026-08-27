// swift-tools-version: 999.0
import PackageDescription

// This workspace declares a source-control dependency on
// `external/some-lib`. A companion `.swiftpm/configuration/workspace-overrides.json`
// (gitignored in real projects; checked in here to exercise the
// end-to-end override pipeline) redirects `some-lib` to a local
// filesystem checkout at `external/local-some-lib`. The redirect is
// applied at workspace-manifest load time, so `swift package resolve`
// and `swift build` see only the local path — the source-control
// URL is never contacted.
let workspace = Workspace(
    members: [
        "packages/app",
    ],
    dependencies: [
        .package(url: "external/some-lib", from: "1.0.0"),
    ],
)
