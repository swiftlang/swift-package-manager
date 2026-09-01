// swift-tools-version: 999.0
import PackageDescription

// S15_WorkspaceInheritedCycle fixture: a workspace declares one
// member (`lib-a`) and one workspace-level dependency `lib-x`. The
// cycle is formed at the target level:
//
//   LibA -> LibX product (via `.package(workspaceInherited: "lib-x")`)
//   LibX -> LibA product (via `.package(path: "../../packages/lib-a")`
//                         declared in `external/lib-x/Package.swift`)
//
// Graph load must reject the target cycle with a
// `cyclic dependency declaration` diagnostic. Locks in that
// `.workspaceInherited` edges participate in cycle detection just
// like the concrete kind they resolve to (`.fileSystem` in this
// fixture).
let workspace = Workspace(
    members: [
        "packages/lib-a",
    ],
    dependencies: [
        .package(path: "external/lib-x"),
    ],
)
