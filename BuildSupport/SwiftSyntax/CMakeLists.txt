include(FetchContent)

# Ensure that the SwiftSyntax symbols we use are disjoint from elsewhere in
# the compiler toolchain.
set(SWIFT_MODULE_ABI_NAME_PREFIX "_PM")

# Use separate target names so the underlying libraries have a prefix separate
# from the rest of the toolchain.
set(SWIFTSYNTAX_TARGET_NAMESPACE "_PM")

# Handle installation on our own.
set(SWIFT_SYNTAX_INSTALL_TARGETS NO)
if(DEFINED SWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE)
  file(TO_CMAKE_PATH "${SWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE}" swift_syntax_path)
  FetchContent_Declare(SwiftSyntax
    SOURCE_DIR "${swift_syntax_path}")
else()
  FetchContent_Declare(SwiftSyntax
    GIT_REPOSITORY https://github.com/swiftlang/swift-syntax
    GIT_TAG main)
endif()
FetchContent_MakeAvailable(SwiftSyntax)

# FIXME: Use FetchContent_Declare's EXCLUDE_FROM_ALL after CMake 3.28
FetchContent_GetProperties(SwiftSyntax BINARY_DIR binary_dir)
set_property(DIRECTORY "${binary_dir}" PROPERTY EXCLUDE_FROM_ALL TRUE)

# Install SwiftPM versions of the swift-syntax libraries we use.
set(SWIFTPM_SWIFT_SYNTAX_MODULES
  _PMSwiftBasicFormat
  _PMSwiftIfConfig
  _PMSwiftParser
  _PMSwiftParserDiagnostics
  _PMSwiftDiagnostics
  _PMSwiftSyntax
  _PMSwiftOperators
  _PMSwiftSyntaxBuilder
  _PMSwiftIDEUtils
  _PMSwiftRefactor
)

set(SWIFT_HOST_LIBRARIES_SUBDIRECTORY "swift/host")
foreach(target ${SWIFTPM_SWIFT_SYNTAX_MODULES})
    install(TARGETS ${target}
      LIBRARY DESTINATION lib/${SWIFT_HOST_LIBRARIES_SUBDIRECTORY}
      RUNTIME DESTINATION bin
    )
endforeach()
