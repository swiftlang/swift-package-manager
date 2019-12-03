cmake_minimum_required(VERSION 3.15.1)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules)

project(SwiftPM-Installer LANGUAGES Swift)

foreach(BINARY swift-build swift-test swift-package swift-run)
    install(FILES 
        ${SWIFTPM_BUILD_DIR}/${BINARY}
        DESTINATION bin)
endforeach()

install(FILES 
    ${SWIFTPM_BUILD_DIR}/swiftpm-xctest-helper
    DESTINATION libexec/swift/pm)

if(INSTALL_LIBSWIFTPM)

list(APPEND LIBSPM_MODULES TSCLibc)
list(APPEND LIBSPM_MODULES TSCBasic)
list(APPEND LIBSPM_MODULES TSCUtility)

list(APPEND LIBSPM_MODULES Build)
list(APPEND LIBSPM_MODULES Commands)
list(APPEND LIBSPM_MODULES PackageGraph)
list(APPEND LIBSPM_MODULES PackageLoading)
list(APPEND LIBSPM_MODULES PackageModel)
list(APPEND LIBSPM_MODULES SourceControl)
list(APPEND LIBSPM_MODULES SPMLLBuild)
list(APPEND LIBSPM_MODULES Workspace)
list(APPEND LIBSPM_MODULES Xcodeproj)

foreach(MODULE ${LIBSPM_MODULES})
    install(FILES 
        ${SWIFTPM_BUILD_DIR}/${MODULE}.swiftmodule
        ${SWIFTPM_BUILD_DIR}/${MODULE}.swiftdoc
        DESTINATION local/lib/swift/pm)
endforeach()

install(DIRECTORY
    ${PROJECT_SOURCE_DIR}/Sources/TSCclibc/include/
    DESTINATION local/lib/swift/pm/clibc)

install(FILES 
    ${SWIFTPM_BUILD_DIR}/libSwiftPM${CMAKE_SHARED_LIBRARY_SUFFIX}
    DESTINATION local/lib/swift/pm)
endif()
