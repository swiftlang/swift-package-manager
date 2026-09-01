// swift-tools-version: 999.0
import PackageDescription

// S15_MemberTraits fixture: a workspace declares three members
// (`app`, `lib-a`, `lib-b`). Both `app` and `lib-b` reference the
// sibling workspace member `lib-a` via `.package(workspaceMember:)`
// but with DIFFERENT per-consumer trait sets — `app` requests
// `["extras"]`, `lib-b` requests `["perf"]`. This exercises the
// per-member trait preservation for `.workspaceMember` end-to-end
// (there is no workspace-level counterpart to union with, unlike
// `.workspaceInherited`; the authored trait set is preserved
// verbatim, one set per consumer).
let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
        "packages/lib-b",
    ],
)
