# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(_AsyncFileSystem
  AsyncFileSystem.swift
  ConcurrencySupport.swift
  MockFileSystem.swift
  OpenReadableFile.swift
  OpenWritableFile.swift
  ReadableFileStream.swift
  WritableStream.swift
)
target_link_libraries(_AsyncFileSystem PRIVATE
  SwiftSystem::SystemPackage)

# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(_AsyncFileSystem PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS _AsyncFileSystem
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)

set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS _AsyncFileSystem)
