/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType


func productRef(module: Module) -> String {
    return "ProductModule\(module.c99name)"
}

func productsGroupRef(module: Module) -> String {
    return "Product\(module.c99name)"
}

func productBuildPhase(module: Module) -> String {
    return "ProductBuildPhase\(module.c99name)"
}

func productBuildConfigurationList(module: Module) -> String {
    return "ProductBuildConfigurationList\(module.c99name)"
}

func productBuildConfiguration(module: Module) -> String {
    return "ProductBuildConfiguration\(module.c99name)"
}

func sourceFileRefs(module: SwiftModule) -> [(String, String)] {
    let prefix = module.c99name

    return module.sources.relativePaths.map {
        return ("\(prefix)\($0.hashValue)", $0)
    }
}

func sourcesBuildPhaseFileRefs(module: SwiftModule) -> [(String, String)] {
    return sourceFileRefs(module).map{ ($0.0, "BuildPhaseFileRef\($0.0)") }
}

func productBuildPhaseFileRef(module: Module) -> String {
    return "ProductBuildPhaseFileRef\(module.c99name)"
}

func moduleGroupName(module: Module) -> String {
    return "Group\(module.c99name)"
}

func targetDependency(module: Module) -> String {
    return "TargetDependency\(module.c99name)"
}

func targetDependencyProxy(module: Module) -> String {
    return "TargetDependencyProxy\(module.c99name)"
}

func linkBuildPhase(module module: Module) -> String {
    return "LinkBuildPhase\(module.c99name)"
}

extension SwiftModule {
    private var isLibrary: Bool {
        return type == .Library
    }

    var type: String {
        if self is TestModule {
            return "com.apple.product-type.bundle.unit-test"
        } else if isLibrary {
            return "com.apple.product-type.library.dynamic"
        } else {
            return "com.apple.product-type.tool"
        }
    }

    var explicitFileType: String {
        if self is TestModule {
            return "wrapper.cfbundle"
        } else if isLibrary {
            return "dylib"
        } else {
            return "executable"
        }
    }

    var productPath: String {
        if self is TestModule {
            return "\(c99name).xctest"
        } else if isLibrary {
            return "\(c99name).dylib"
        } else {
            return name
        }
    }

    var linkBuildPhaseFiles: String {
        return recursiveDependencies.map(productBuildPhaseFileRef).joinWithSeparator(", ")
    }

    var nativeTargetDependencies: String {
        return dependencies.map(targetDependency).joinWithSeparator(", ")
    }

    var productName: String {
        if isLibrary && !(self is TestModule) {
            // you can go without a lib prefix, but something unexpected will break
            return "'lib$(TARGET_NAME)'"
        } else {
            return "'$(TARGET_NAME)'"
        }
    }

    var buildSettings: String {
        var buildSettings = ["PRODUCT_NAME": productName]
        buildSettings["PRODUCT_MODULE_NAME"] = c99name
        buildSettings["OTHER_SWIFT_FLAGS"] = "-DXcode"
        buildSettings["MACOSX_DEPLOYMENT_TARGET"] = "'10.10'"
        buildSettings["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"

        if self is TestModule {
            buildSettings["EMBEDDED_CONTENT_CONTAINS_SWIFT"] = "YES"

            //FIXME this should not be required
            buildSettings["LD_RUNPATH_SEARCH_PATHS"] = "'@loader_path/../Frameworks'"
        } else {
            //FIXME Xcode fails to set this for some reason
            buildSettings["LD_RUNPATH_SEARCH_PATHS"] = "/Users/mxcl/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2016-03-01-a.xctoolchain/usr/lib/swift/macosx"

            if isLibrary {
                buildSettings["ENABLE_TESTABILITY"] = "YES"
                buildSettings["DYLIB_INSTALL_NAME_BASE"] = "'$(CONFIGURATION_BUILD_DIR)'"
            } else {
                // override default behavior, instead link dynamically
                buildSettings["SWIFT_FORCE_STATIC_LINK_STDLIB"] = "NO"
                buildSettings["SWIFT_FORCE_DYNAMIC_LINK_STDLIB"] = "YES"
            }
        }

        return buildSettings.map{ "\($0) = \($1);" }.joinWithSeparator(" ")
    }
}


extension SwiftModule {
    var blueprintIdentifier: String {
        return productsGroupRef(self)
    }

    var buildableName: String {
        if isLibrary && !(self is TestModule) {
            return "lib\(productPath)"
        } else {
            return productPath
        }
    }

    var blueprintName: String {
        return name
    }
}
