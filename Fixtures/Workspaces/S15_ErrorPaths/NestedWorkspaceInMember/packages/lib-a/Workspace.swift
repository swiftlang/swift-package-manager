// swift-tools-version: 999.0
import PackageDescription

// The stray nested Workspace.swift inside a member's directory —
// what the outer workspace's load-time validation must catch.
let workspace = Workspace(
    members: [],
)
