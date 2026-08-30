// swift-tools-version: 999.0
import PackageDescription

// S15_ErrorPaths/MemberWithoutPackageSwift fixture: the declared
// member directory exists but has no Package.swift inside.
// Load-time validation must reject this and name the offending
// member so the author knows which entry to fix.
let workspace = Workspace(
    members: [
        "packages/lib-a",
    ],
)
