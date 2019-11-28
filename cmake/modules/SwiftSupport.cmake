# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

# Returns the current architecture name in a variable
#
# Usage:
#   get_swift_host_arch(result_var_name)
#
# If the current architecture is supported by Swift, sets ${result_var_name}
# with the sanitized host architecture name derived from CMAKE_SYSTEM_PROCESSOR.
function(get_swift_host_arch result_var_name)
  if("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "x86_64")
    set("${result_var_name}" "x86_64" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "aarch64")
    set("${result_var_name}" "aarch64" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "ppc64")
    set("${result_var_name}" "powerpc64" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "ppc64le")
    set("${result_var_name}" "powerpc64le" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "s390x")
    set("${result_var_name}" "s390x" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "armv6l")
    set("${result_var_name}" "armv6" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "armv7l")
    set("${result_var_name}" "armv7" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "armv7-a")
    set("${result_var_name}" "armv7" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "AMD64")
    set("${result_var_name}" "x86_64" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "IA64")
    set("${result_var_name}" "itanium" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "x86")
    set("${result_var_name}" "i686" PARENT_SCOPE)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "i686")
    set("${result_var_name}" "i686" PARENT_SCOPE)
  else()
    message(FATAL_ERROR "Unrecognized architecture on host system: ${CMAKE_SYSTEM_PROCESSOR}")
  endif()
endfunction()
