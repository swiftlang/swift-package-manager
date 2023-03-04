# This source file is part of the Swift open source project
#
# Copyright (c) 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageSigning STATIC
  embedded_resources.swift
  CertificateStores.swift
  SigningEntity/FilePackageSigningEntityStorage.swift
  SigningEntity/PackageSigningEntityStorage.swift
  SigningEntity/SigningEntity.swift
  SignatureProvider.swift
  SigningIdentity.swift
  VerifierPolicies.swift
  X509Extensions.swift)
target_link_libraries(PackageSigning PUBLIC
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>
  Basics
  Crypto
  PackageModel
  TSCBasic
  TSCUtility
  X509)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageSigning PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS PackageSigning)
