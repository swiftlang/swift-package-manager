// swift-tools-version: 999.0
import PackageDescription

// The INNER workspace: a valid Workspace.swift whose load must
// fail because an ancestor directory contains another
// Workspace.swift (the outer fixture root).
let workspace = Workspace(
    members: [
        "packages/lib-a",
    ],
)
