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

SET(CMAKE_Swift_FLAGS "${CMAKE_Swift_FLAGS} -Xlinker -rpath -Xlinker ${CMAKE_BINARY_DIR}")
include_directories(${CMAKE_SOURCE_DIR}/Sources/clibc/include)
add_library(clibc STATIC Sources/clibc/libc.c)
# ==================== SPMLibc ==================== #
file(GLOB SPMLibc_SRC Sources/SPMLibc/*.swift)
add_library(SPMLibc
Sources/SPMLibc/libc.swift
)
target_link_libraries(SPMLibc
    clibc)
set_target_properties(SPMLibc PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== Basic ==================== #
file(GLOB Basic_SRC Sources/Basic/*.swift)
add_library(Basic
Sources/Basic/Await.swift
Sources/Basic/ByteString.swift
Sources/Basic/CStringArray.swift
Sources/Basic/CacheableSequence.swift
Sources/Basic/CollectionAlgorithms.swift
Sources/Basic/CollectionExtensions.swift
Sources/Basic/Condition.swift
Sources/Basic/DeltaAlgorithm.swift
Sources/Basic/DiagnosticsEngine.swift
Sources/Basic/DictionaryExtensions.swift
Sources/Basic/DictionaryLiteralExtensions.swift
Sources/Basic/EditDistance.swift
Sources/Basic/FileInfo.swift
Sources/Basic/FileSystem.swift
Sources/Basic/GraphAlgorithms.swift
Sources/Basic/JSON.swift
Sources/Basic/JSONMapper.swift
Sources/Basic/KeyedPair.swift
Sources/Basic/LazyCache.swift
Sources/Basic/Lock.swift
Sources/Basic/ObjectIdentifierProtocol.swift
Sources/Basic/OrderedDictionary.swift
Sources/Basic/OrderedSet.swift
Sources/Basic/OutputByteStream.swift
Sources/Basic/Path.swift
Sources/Basic/PathShims.swift
Sources/Basic/Process.swift
Sources/Basic/ProcessEnv.swift
Sources/Basic/ProcessSet.swift
Sources/Basic/RegEx.swift
Sources/Basic/Result.swift
Sources/Basic/SHA256.swift
Sources/Basic/SortedArray.swift
Sources/Basic/StringConversions.swift
Sources/Basic/SynchronizedQueue.swift
Sources/Basic/TemporaryFile.swift
Sources/Basic/TerminalController.swift
Sources/Basic/Thread.swift
Sources/Basic/Tuple.swift
Sources/Basic/misc.swift
)
target_link_libraries(Basic
    SPMLibc)
set_target_properties(Basic PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== SPMUtility ==================== #
file(GLOB SPMUtility_SRC Sources/SPMUtility/*.swift)
add_library(SPMUtility
Sources/SPMUtility/ArgumentParser.swift
Sources/SPMUtility/ArgumentParserShellCompletion.swift
Sources/SPMUtility/BuildFlags.swift
Sources/SPMUtility/CollectionExtensions.swift
Sources/SPMUtility/Diagnostics.swift
Sources/SPMUtility/FSWatch.swift
Sources/SPMUtility/Git.swift
Sources/SPMUtility/InterruptHandler.swift
Sources/SPMUtility/PkgConfig.swift
Sources/SPMUtility/Platform.swift
Sources/SPMUtility/Process.swift
Sources/SPMUtility/ProgressAnimation.swift
Sources/SPMUtility/SimplePersistence.swift
Sources/SPMUtility/StringExtensions.swift
Sources/SPMUtility/StringMangling.swift
Sources/SPMUtility/URL.swift
Sources/SPMUtility/Verbosity.swift
Sources/SPMUtility/Version.swift
Sources/SPMUtility/Versioning.swift
Sources/SPMUtility/misc.swift
)
target_link_libraries(SPMUtility
    Basic)
set_target_properties(SPMUtility PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== SourceControl ==================== #
file(GLOB SourceControl_SRC Sources/SourceControl/*.swift)
add_library(SourceControl
Sources/SourceControl/GitRepository.swift
Sources/SourceControl/InMemoryGitRepository.swift
Sources/SourceControl/Repository.swift
Sources/SourceControl/RepositoryManager.swift
Sources/SourceControl/SwiftPMConfig.swift
)
target_link_libraries(SourceControl
    Basic SPMUtility)
set_target_properties(SourceControl PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== SPMLLBuild ==================== #
file(GLOB SPMLLBuild_SRC Sources/SPMLLBuild/*.swift)
add_library(SPMLLBuild
Sources/SPMLLBuild/llbuild.swift
)
target_link_libraries(SPMLLBuild
    Basic SPMUtility)
set_target_properties(SPMLLBuild PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== PackageModel ==================== #
file(GLOB PackageModel_SRC Sources/PackageModel/*.swift)
add_library(PackageModel
Sources/PackageModel/BuildSettings.swift
Sources/PackageModel/Manifest.swift
Sources/PackageModel/Package.swift
Sources/PackageModel/PackageModel+Codable.swift
Sources/PackageModel/Platform.swift
Sources/PackageModel/Product.swift
Sources/PackageModel/ResolvedModels.swift
Sources/PackageModel/Sources.swift
Sources/PackageModel/Target.swift
Sources/PackageModel/ToolsVersion.swift
)
target_link_libraries(PackageModel
    Basic SPMUtility)
set_target_properties(PackageModel PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== PackageLoading ==================== #
file(GLOB PackageLoading_SRC Sources/PackageLoading/*.swift)
add_library(PackageLoading
Sources/PackageLoading/Diagnostics.swift
Sources/PackageLoading/ManifestBuilder.swift
Sources/PackageLoading/ManifestLoader.swift
Sources/PackageLoading/ModuleMapGenerator.swift
Sources/PackageLoading/PackageBuilder.swift
Sources/PackageLoading/PackageDescription4Loader.swift
Sources/PackageLoading/Target+PkgConfig.swift
Sources/PackageLoading/ToolsVersionLoader.swift
)
target_link_libraries(PackageLoading
    Basic PackageModel SPMUtility SPMLLBuild)
set_target_properties(PackageLoading PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== PackageGraph ==================== #
file(GLOB PackageGraph_SRC Sources/PackageGraph/*.swift)
add_library(PackageGraph
Sources/PackageGraph/DependencyResolver.swift
Sources/PackageGraph/PackageGraph.swift
Sources/PackageGraph/PackageGraphLoader.swift
Sources/PackageGraph/PackageGraphRoot.swift
Sources/PackageGraph/Pubgrub.swift
Sources/PackageGraph/RawPackageConstraints.swift
Sources/PackageGraph/RepositoryPackageContainerProvider.swift
)
target_link_libraries(PackageGraph
    Basic PackageLoading PackageModel SourceControl SPMUtility)
set_target_properties(PackageGraph PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== Build ==================== #
file(GLOB Build_SRC Sources/Build/*.swift)
add_library(Build
Sources/Build/BuildDelegate.swift
Sources/Build/BuildPlan.swift
Sources/Build/Command.swift
Sources/Build/Sanitizers.swift
Sources/Build/SwiftCompilerOutputParser.swift
Sources/Build/ToolProtocol.swift
Sources/Build/Toolchain.swift
Sources/Build/Triple.swift
Sources/Build/llbuild.swift
)
target_link_libraries(Build
    Basic PackageGraph)
set_target_properties(Build PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== Xcodeproj ==================== #
file(GLOB Xcodeproj_SRC Sources/Xcodeproj/*.swift)
add_library(Xcodeproj
Sources/Xcodeproj/PropertyList.swift
Sources/Xcodeproj/SchemesGenerator.swift
Sources/Xcodeproj/Target+PBXProj.swift
Sources/Xcodeproj/XcodeProjectModel.swift
Sources/Xcodeproj/XcodeProjectModelSerialization.swift
Sources/Xcodeproj/generate.swift
Sources/Xcodeproj/pbxproj.swift
)
target_link_libraries(Xcodeproj
    Basic PackageGraph)
set_target_properties(Xcodeproj PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== Workspace ==================== #
file(GLOB Workspace_SRC Sources/Workspace/*.swift)
add_library(Workspace
Sources/Workspace/CheckoutState.swift
Sources/Workspace/Destination.swift
Sources/Workspace/Diagnostics.swift
Sources/Workspace/Export.swift
Sources/Workspace/InitPackage.swift
Sources/Workspace/ManagedDependency.swift
Sources/Workspace/PinsStore.swift
Sources/Workspace/ToolsVersionWriter.swift
Sources/Workspace/UserToolchain.swift
Sources/Workspace/Workspace.swift
)
target_link_libraries(Workspace
    Basic Build PackageGraph PackageModel SourceControl Xcodeproj)
set_target_properties(Workspace PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
# ==================== Commands ==================== #
file(GLOB Commands_SRC Sources/Commands/*.swift)
add_library(Commands
Sources/Commands/Completions+bash.swift
Sources/Commands/Completions+zsh.swift
Sources/Commands/Describe.swift
Sources/Commands/Error.swift
Sources/Commands/GenerateLinuxMain.swift
Sources/Commands/Options.swift
Sources/Commands/SwiftBuildTool.swift
Sources/Commands/SwiftPackageTool.swift
Sources/Commands/SwiftRunTool.swift
Sources/Commands/SwiftTestTool.swift
Sources/Commands/SwiftTool.swift
Sources/Commands/WatchmanHelper.swift
Sources/Commands/show-dependencies.swift
)
target_link_libraries(Commands
    Basic Build PackageGraph SourceControl SPMUtility Xcodeproj Workspace)
set_target_properties(Commands PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
file(GLOB swiftbuild_SRC Sources/swift-build/*.swift)
add_executable(swift-build
    ${swiftbuild_SRC}
)
target_link_libraries(swift-build
    Commands)

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
