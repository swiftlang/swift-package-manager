// swift-tools-version: 999.0
import PackageDescription

// S15_ErrorPaths/EmptyMembers fixture: a syntactically valid
// Workspace.swift with an empty `members: []` array. The parser
// accepts this shape (it's DSL-valid), but load-time validation
// rejects it — every workspace needs at least one member.
let workspace = Workspace(
    members: [],
)
