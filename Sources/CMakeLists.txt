# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_subdirectory(Basic)
add_subdirectory(Build)
add_subdirectory(clibc)
add_subdirectory(Commands)
add_subdirectory(PackageDescription4)
add_subdirectory(PackageGraph)
add_subdirectory(PackageLoading)
add_subdirectory(PackageModel)
add_subdirectory(SourceControl)
add_subdirectory(SPMLibc)
add_subdirectory(SPMLLBuild)
add_subdirectory(SPMUtility)
add_subdirectory(swift-build)
add_subdirectory(swift-package)
add_subdirectory(swift-run)
add_subdirectory(swift-test)
if(CMAKE_SYSTEM_NAME STREQUAL Darwin)
  add_subdirectory(swiftpm-xctest-helper)
endif()
add_subdirectory(Workspace)
add_subdirectory(Xcodeproj)
