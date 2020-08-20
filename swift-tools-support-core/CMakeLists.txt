cmake_minimum_required(VERSION 3.15.1)

project(SwiftTSC LANGUAGES C Swift)

set(SWIFT_VERSION 5)
set(CMAKE_Swift_LANGUAGE_VERSION ${SWIFT_VERSION})
if(CMAKE_VERSION VERSION_LESS 3.16)
    add_compile_options($<$<COMPILE_LANGUAGE:Swift>:-swift-version$<SEMICOLON>${SWIFT_VERSION}>)
    # Workaround for CMake 3.15 which doesn't link libraries properly on Windows
    set(CMAKE_LINK_LIBRARY_FLAG "-l")
endif()

set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)

if(CMAKE_VERSION VERSION_LESS 3.16 AND CMAKE_SYSTEM_NAME STREQUAL Windows)
  set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
  set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
else()
  set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
  set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
endif()
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)

find_package(dispatch QUIET)
find_package(Foundation QUIET)
find_package(SQLite3 REQUIRED)

add_subdirectory(Sources)
add_subdirectory(cmake/modules)
