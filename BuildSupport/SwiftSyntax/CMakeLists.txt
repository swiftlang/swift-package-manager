include(FetchContent)

set(BUILD_SHARED_LIBS OFF)

if(DEFINED SWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE)
  file(TO_CMAKE_PATH "${SWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE}" swift_syntax_path)
  FetchContent_Declare(SwiftSyntax
    SOURCE_DIR "${swift_syntax_path}")
else()
  FetchContent_Declare(SwiftSyntax
    GIT_REPOSITORY https://github.com/apple/swift-syntax
    GIT_TAG main)
endif()
FetchContent_MakeAvailable(SwiftSyntax)
