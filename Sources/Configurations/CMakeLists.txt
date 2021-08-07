# This source file is part of the Swift.org open source project
#
# Copyright (c) 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Configurations
  Configuration.swift
  Configuration+Collections.swift
  Configuration+ManifestLoading.swift
  Configuration+Mirrors.swift
  Configuration+Netrc.swift
  Configuration+Resolution.swift
  Locations.swift
  Utilities.swift)
target_link_libraries(Configurations PUBLIC
  Basics
  TSCBasic
  TSCUtility)
target_link_libraries(Configurations PRIVATE
   TSCclibc)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(Configurations PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(USE_CMAKE_INSTALL)
install(TARGETS Configurations
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS Configurations)
