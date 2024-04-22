SET(SWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE ${CMAKE_SOURCE_DIR}/../swift-syntax)
message(STATUS "swift-syntax path: ${SWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE}")

include(FetchContent)

if(NOT EXISTS "${SWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE}")
  message(SEND_ERROR "swift-syntax is required to build SwiftPM. Please run update-checkout or specify SWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE")
  return()
endif()

# Build swift-syntax libraries with FetchContent.
# set(CMAKE_Swift_COMPILER_TARGET ${SWIFT_HOST_TRIPLE})
set(BUILD_SHARED_LIBS OFF)

file(TO_CMAKE_PATH "${SWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE}" swift_syntax_path)
FetchContent_Declare(SwiftSyntax SOURCE_DIR "${swift_syntax_path}")
FetchContent_MakeAvailable(SwiftSyntax)
