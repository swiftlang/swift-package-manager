# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SPMSQLite3 INTERFACE)
target_include_directories(SPMSQLite3 INTERFACE
  ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(SPMSQLite3 INTERFACE
  SQLite::SQLite3)
if(CMAKE_SYSTEM_NAME STREQUAL OpenBSD)
  target_link_options(SPMSQLite3 INTERFACE "-L/usr/local/lib")
endif()
