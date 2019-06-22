cmake_minimum_required(VERSION 3.14.20190603)

project(SwiftPM LANGUAGES C Swift)

# Place all modules into `swift` in the root of the build tree.
set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)

# enable shared libraries by default.
option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)

# Get the SDK path for macOS.
execute_process(
    COMMAND xcrun --sdk macosx --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE)

SET(CMAKE_Swift_FLAGS "${CMAKE_Swift_FLAGS} -sdk ${CMAKE_OSX_SYSROOT}")
SET(CMAKE_Swift_FLAGS "${CMAKE_Swift_FLAGS} -swift-version 4.2")

# For llbuild.
option(LLBUILD_FRAMEWORK "Path to llbuild framework" "")
option(LLBUILD_LIBRARY "Path to llbuild library" "")
option(LLBUILD_SRC "Path to llbuild sources" "")

if(LLBUILD_FRAMEWORK)
    message("==== Using llbuild framework at ${LLBUILD_FRAMEWORK}")
    SET(CMAKE_Swift_FLAGS "${CMAKE_Swift_FLAGS} -F${LLBUILD_FRAMEWORK}")
    SET(CMAKE_Swift_FLAGS "${CMAKE_Swift_FLAGS} -Xlinker -rpath -Xlinker ${LLBUILD_FRAMEWORK}")
elseif(LLBUILD_BUILD_DIR)
    if(NOT LLBUILD_SRC)
        message(FATAL_ERROR "Need LLBUILD_SRC when using LLBUILD_LIBRARY")
    endif()
    message("==== Using llbuild build dir at ${LLBUILD_BUILD_DIR}")
    message("==== Using llbuild src at ${LLBUILD_SRC}")
    SET(CMAKE_Swift_FLAGS "${CMAKE_Swift_FLAGS} -I${LLBUILD_BUILD_DIR}/products/llbuildSwift")
    SET(CMAKE_Swift_FLAGS "${CMAKE_Swift_FLAGS} -I${LLBUILD_SRC}/products/libllbuild/include")
    SET(CMAKE_Swift_FLAGS "${CMAKE_Swift_FLAGS} -L${LLBUILD_BUILD_DIR}/lib")
    SET(CMAKE_Swift_FLAGS "${CMAKE_Swift_FLAGS} -Xlinker -rpath -Xlinker ${LLBUILD_BUILD_DIR}/lib")
else()
    message(FATAL_ERROR "Need LLBUILD_FRAMEWORK or LLBUILD_SRC + LLBUILD_LIBRARY")
endif()

include_directories(${CMAKE_SOURCE_DIR}/Sources/clibc/include)

# ================== Libc ===================== #
add_library(clibc STATIC
    Sources/clibc/libc.c)

# ================== SPMLibc ===================== #
add_library(SPMLibc
    Sources/SPMLibc/libc.swift)
target_link_libraries(SPMLibc
  clibc)
set_target_properties(SPMLibc PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== Basic ===================== #
file(GLOB BASIC_SRC Sources/Basic/*.swift)
add_library(Basic
    ${BASIC_SRC}
)
target_link_libraries(Basic
    SPMLibc)
set_target_properties(Basic PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== Utility ===================== #
file(GLOB UTILITY_SRC Sources/SPMUtility/*.swift)
add_library(SPMUtility
    ${UTILITY_SRC}
)
target_link_libraries(SPMUtility
    Basic)
set_target_properties(SPMUtility PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== SourceControl ===================== #
file(GLOB SourceControl_SRC Sources/SourceControl/*.swift)
add_library(SourceControl
    ${SourceControl_SRC}
)
target_link_libraries(SourceControl
    SPMUtility)
set_target_properties(SourceControl PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== SPMLLBuild ===================== #
file(GLOB SPMLLBuild_SRC Sources/SPMLLBuild/*.swift)
add_library(SPMLLBuild
    ${SPMLLBuild_SRC}
)
target_link_libraries(SPMLLBuild
    SPMUtility)
set_target_properties(SPMLLBuild PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== PackageModel ===================== #
file(GLOB PackageModel_SRC Sources/PackageModel/*.swift)
add_library(PackageModel
    ${PackageModel_SRC}
)
target_link_libraries(PackageModel
    SPMUtility)
set_target_properties(PackageModel PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== PackageLoading ===================== #
file(GLOB PackageLoading_SRC Sources/PackageLoading/*.swift)
add_library(PackageLoading
    ${PackageLoading_SRC}
)
target_link_libraries(PackageLoading
    PackageModel SPMLLBuild
)
set_target_properties(PackageLoading PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== PackageGraph ===================== #
file(GLOB PackageGraph_SRC Sources/PackageGraph/*.swift)
add_library(PackageGraph
    ${PackageGraph_SRC}
)
target_link_libraries(PackageGraph
    PackageLoading SourceControl)
set_target_properties(PackageGraph PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== Build ===================== #
file(GLOB Build_SRC Sources/Build/*.swift)
add_library(Build
    ${Build_SRC}
)
target_link_libraries(Build
    PackageGraph)
set_target_properties(Build PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== Xcodeproj ===================== #
file(GLOB Xcodeproj_SRC Sources/Xcodeproj/*.swift)
add_library(Xcodeproj
    ${Xcodeproj_SRC}
)
target_link_libraries(Xcodeproj
    PackageGraph)
set_target_properties(Xcodeproj PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== Workspace ===================== #
file(GLOB Workspace_SRC Sources/Workspace/*.swift)
add_library(Workspace
    ${Workspace_SRC}
)
target_link_libraries(Workspace
    Build SourceControl)
set_target_properties(Workspace PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== Commands ===================== #
file(GLOB Commands_SRC Sources/Commands/*.swift)
add_library(Commands
    ${Commands_SRC}
)
target_link_libraries(Commands
    Workspace Xcodeproj)
set_target_properties(Commands PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

# ================== swift-build ===================== #
file(GLOB swiftbuild_SRC Sources/swift-build/*.swift)
add_executable(swift-build
    ${swiftbuild_SRC}
)
target_link_libraries(swift-build
    Commands)

# ================== PD_4 ===================== #
file(GLOB PD_SRC Sources/PackageDescription4/*.swift)

add_library(PD4
    ${PD_SRC}
)
set_target_properties(PD4 PROPERTIES
  Swift_MODULE_NAME PackageDescription
  Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/runtimes/4
  OUTPUT_NAME PackageDescription
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/runtimes/4
)
target_compile_definitions(PD4 PRIVATE PACKAGE_DESCRIPTION_4)

# ================== PD_4_2 ===================== #
add_library(PD4_2
    ${PD_SRC}
)
set_target_properties(PD4_2 PROPERTIES
  Swift_MODULE_NAME PackageDescription
  Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/runtimes/4_2
  OUTPUT_NAME PackageDescription
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/runtimes/4_2
)
target_compile_definitions(PD4_2 PRIVATE PACKAGE_DESCRIPTION_4_2)
