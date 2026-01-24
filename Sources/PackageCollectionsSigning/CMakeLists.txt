# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageCollectionsSigning
  CertificatePolicy.swift
  PackageCollectionSigning.swift
  Signature.swift
  Utilities/Base64URL.swift
  Utilities/Utilities.swift
  X509Extensions.swift
  embedded_resources.swift)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageCollectionsSigning PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(PackageCollectionsSigning PUBLIC
  Basics
  PackageCollectionsModel
  Crypto
  _CryptoExtras
  SwiftASN1
  X509)
if(NOT APPLE)
  if(Foundation_FOUND)
    target_link_directories(PackageCollectionsSigning PRIVATE
      $<TARGET_LINKER_FILE_DIR:Fooundation>)
  endif()
  if(dispatch_FOUND)
    target_link_directories(PackageCollectionsSigning PRIVATE
      $<TARGET_LINKER_FILE_DIR:dispatch>)
  endif()
endif()

install(TARGETS PackageCollectionsSigning
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
