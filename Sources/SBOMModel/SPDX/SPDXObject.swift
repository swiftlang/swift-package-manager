//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A protocol representing any object that can be part of an SPDX graph.
/// All SPDX types (Agent, CreationInfo, Document, Package, Relationship, etc.)
/// conform to this protocol to provide type safety when building SPDX graphs.
internal protocol SPDXObject: Codable, Equatable {}

// Conformance for all SPDX types
extension SPDXAgent: SPDXObject {}
extension SPDXCreationInfo: SPDXObject {}
extension SPDXDocument: SPDXObject {}
extension SPDXPackage: SPDXObject {}
extension SPDXRelationship: SPDXObject {}
extension SPDXExternalIdentifier: SPDXObject {}
extension SPDXSBOM: SPDXObject {}
extension SPDXLicenseExpression: SPDXObject {}
