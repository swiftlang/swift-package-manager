##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2025 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

# Install the generated swift interface files for the target.
function(install_swift_interface target)
  # Swiftmodules are already in the directory structure
  get_target_property(module_name ${target} Swift_MODULE_NAME)
  if(NOT module_name)
    set(module_name ${target})
  endif()

  install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${module_name}.swiftmodule"
    DESTINATION "${${PROJECT_NAME}_INSTALL_SWIFTMODULEDIR}"
    COMPONENT ${PROJECT_NAME}_development)
endfunction()
