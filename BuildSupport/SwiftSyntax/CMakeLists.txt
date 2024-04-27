include(FetchContent)

set(CMAKE_FIND_DEBUG_MODE TRUE)
message(STATUS "DEBUGNONSENSE find_package(SwiftSyntax)")
find_package(SwiftSyntax CONFIG)
message(STATUS "DEBUGNONSENSE find_package(SwiftSyntax) complete: FOUND is ${SwiftSyntax_FOUND}")
set(CMAKE_FIND_DEBUG_MODE FALSE)

if(NOT SwiftSyntax_FOUND)
  message(STATUS "DEBUGNONSENSE In NOT SwiftSyntax_FOUND")
  set(SWIFT_SYNTAX_INSTALL_TARGETS YES)
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
endif()

if (NOT TARGET SwiftSyntax)
  message(STATUS "DEBUGNONSENSE missing SwiftSyntax")
endif()
if (NOT TARGET SwiftSyntax::SwiftSyntax)
  message(STATUS "DEBUGNONSENSE missing SwiftSyntax::SwiftSyntax")
endif()
