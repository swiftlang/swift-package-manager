/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getenv
import PackageType
import Utility

func platformArgs() -> [String] {
    var args = [String]()

    #if os(OSX)
        args += ["-target", "x86_64-apple-macosx10.10"]

        if let sysroot = Resources.path.sysroot {
            args += ["-sdk", sysroot]
        }
    #endif

    // We support a custom override in conjunction with the
    // bootstrap script to allow embedding an appropriate RPATH for
    // the package manager tools themselves on Linux, so they can be
    // relocated with the Swift compiler.

    //TODO replace with -Xlinker forwarding since we have that now

    if let rpath = getenv("SWIFTPM_EMBED_RPATH") {
        args += ["-Xlinker", "-rpath", "-Xlinker", rpath]
    }

    return args
}

extension Module {
    var Xcc: [String] {
        return recursiveDependencies.flatMap { module -> [String] in
            if let module = module as? CModule {
                let moduleMapPath = Path.join(module.path, "module.modulemap")
                return ["-Xcc", "-fmodule-map-file=\(moduleMapPath)"]
            } else {
                return []
            }
        }
    }

    var targetName: String {
        return "<\(name).module>"
    }
}

extension Product {
    var targetName: String {
        switch type {
        case .Library(.Dynamic):
            return "<\(name).dylib>"
        case .Test:
            return "<\(name).test>"
        case .Library(.Static):
            return "<\(name).a>"
        case .Executable:
            return "<\(name).exe>"
        }
    }
}

func infoPlist(test: Product) -> String {

    let bundleExecutable = "Package"
    let bundleID = "org.swift.pm." + test.name
    let bundleName = test.name

    var s = ""
    s += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    s += "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    s += "<plist version=\"1.0\">\n"
    s += "<dict>\n"
    s += "<key>CFBundleDevelopmentRegion</key>\n"
    s += "<string>en</string>\n"
    s += "<key>CFBundleExecutable</key>\n"
    s += "<string>\(bundleExecutable)</string>\n"
    s += "<key>CFBundleIdentifier</key>\n"
    s += "<string>\(bundleID)</string>\n"
    s += "<key>CFBundleInfoDictionaryVersion</key>\n"
    s += "<string>6.0</string>\n"
    s += "<key>CFBundleName</key>\n"
    s += "<string>\(bundleName)</string>\n"
    s += "<key>CFBundlePackageType</key>\n"
    s += "<string>BNDL</string>\n"
    s += "<key>CFBundleShortVersionString</key>\n"
    s += "<string>1.0</string>\n"
    s += "<key>CFBundleSignature</key>\n"
    s += "<string>????</string>\n"
    s += "<key>CFBundleSupportedPlatforms</key>\n"
    s += "<array>\n"
    s += "<string>MacOSX</string>\n"
    s += "</array>\n"
    s += "<key>CFBundleVersion</key>\n"
    s += "<string>1</string>\n"
    s += "</dict>\n"
    s += "</plist>\n"
    return s
}

// this function because I couldn't make a Buildable
// protocol and then implement an isTest function
// without Swift runtime erroring about "Could not
// convert Array from Objective-C.
// FIXME please improve!
func targetSplitter(modules: [Module], _ products: [Product]) -> ([String], [String]) {
    let (testmodules, nontestmodules) = modules.partition{ $0 is TestModule }
    let (testproducts, nontestproducts) = products.partition{ if case .Test = $0.type { return true } else { return false } }

    let one = testmodules.map{$0.targetName} + testproducts.map{$0.targetName}
    let two = nontestmodules.map{$0.targetName} + nontestproducts.map{$0.targetName}
    
    return (one, two)
}
