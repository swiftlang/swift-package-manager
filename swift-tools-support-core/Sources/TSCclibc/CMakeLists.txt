# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(TSCclibc STATIC
  libc.c process.c)
target_include_directories(TSCclibc PUBLIC
  include)

if(NOT BUILD_SHARED_LIBS)
  install(TARGETS TSCclibc
    ARCHIVE DESTINATION lib)
endif()

set_property(GLOBAL APPEND PROPERTY TSC_EXPORTS TSCclibc)
