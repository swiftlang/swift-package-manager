# This source file is part of the Swift open source project
#
# Copyright (c) 2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SBOMModel
  SBOMCreator.swift
  SBOMError.swift
  SBOMInput.swift
  Core/SBOMCommit.swift
  Core/SBOMComponent.swift
  Core/SBOMDependencies.swift
  Core/SBOMDocument.swift
  Core/SBOMIdentifier.swift
  Core/SBOMLicense.swift
  Core/SBOMMetadata.swift
  Core/SBOMOriginator.swift
  Core/SBOMPerson.swift
  Core/SBOMRelationship.swift
  Core/SBOMSpec.swift
  Core/SBOMTool.swift
  Converter/CycloneDXConverter.swift
  Converter/SPDXConverter.swift
  CycloneDX/CycloneDXComponent.swift
  CycloneDX/CycloneDXConstants.swift
  CycloneDX/CycloneDXDependency.swift
  CycloneDX/CycloneDXDocument.swift
  CycloneDX/CycloneDXLicense.swift
  CycloneDX/CycloneDXMetadata.swift
  CycloneDX/CycloneDXPedigree.swift
  CycloneDX/CycloneDXProperty.swift
  Encoder/SBOMEncoder.swift
  Extractor/PURL.swift
  Extractor/SBOMCache.swift
  Extractor/SBOMDependenciesExtractor.swift
  Extractor/SBOMExtractor.swift
  Extractor/SBOMFilterStrategy.swift
  Extractor/SBOMGraphsConverter.swift
  SPDX/SPDXAgent.swift
  SPDX/SPDXConstants.swift
  SPDX/SPDXCreationInfo.swift
  SPDX/SPDXDocument.swift
  SPDX/SPDXExternalIdentifier.swift
  SPDX/SPDXGraph.swift
  SPDX/SPDXLicenseExpression.swift
  SPDX/SPDXObject.swift
  SPDX/SPDXPackage.swift
  SPDX/SPDXRelationship.swift
  SPDX/SPDXSBOM.swift
  SPDX/SPDXType.swift
  Validator/CycloneDXValidator.swift
  Validator/SBOMSchema.swift
  Validator/SBOMValidator.swift
  Validator/SBOMValidatorProtocol.swift
  Validator/SPDXValidator.swift)
target_link_libraries(SBOMModel PUBLIC
  TSCBasic
  TSCUtility
  Basics
  PackageCollections
  PackageGraph
  PackageModel
  SourceControl
  SwiftBuildSupport
)

# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(SBOMModel PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS SBOMModel
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS SBOMModel)
