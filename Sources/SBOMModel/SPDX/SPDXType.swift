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

internal enum SPDXType: String, Codable, Equatable {
    case Agent
    case CreationInfo
    case SpdxDocument
    case SoftwareSBOM = "software_Sbom"
    case SoftwarePackage = "software_Package"
    case Relationship
    case ExternalIdentifier
    case LicenseExpression = "simplelicensing_LicenseExpression"
}
