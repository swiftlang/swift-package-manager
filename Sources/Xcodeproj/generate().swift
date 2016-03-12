/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility
import POSIX

/** 
 Generates an xcodeproj at the specified path.
 - Returns: the path to the generated project
*/
public func generate(path path: String, package: Package, modules: [SwiftModule], products: [Product]) throws -> String {

    /// If a specific *.xcodeproj path is already passed in, use that. 
    /// Otherwise treat the path as the desired enclosing folder for
    /// the .xcodeproj folder.
    let rootdir = path.hasSuffix(".xcodeproj") ? path : Path.join(path, "\(package.name).xcodeproj")
    try mkdir(rootdir)
    
    let schemedir = try mkdir(rootdir, "xcshareddata/xcschemes")

////// the pbxproj file describes the project and its targets
    try open(rootdir, "project.pbxproj") { fwrite in
        pbxproj(package: package, modules: modules, products: products, printer: fwrite)
    }

////// the scheme acts like an aggregate target for all our targets
   /// it has all tests associated so CMD+U works
    try open(schemedir, "\(package.name).xcscheme") { fwrite in
        xcscheme(packageName: package.name, modules: modules, printer: fwrite)
    }

////// we generate this file to ensure our main scheme is listed
   /// before any inferred schemes Xcode may autocreate
    try open(schemedir, "xcschememanagement.plist") { fwrite in
        fwrite("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        fwrite("<plist version=\"1.0\">")
        fwrite("<dict>")
        fwrite("  <key>SchemeUserState</key>")
        fwrite("  <dict>")
        fwrite("    <key>\(package.name).xcscheme</key>")
        fwrite("    <dict></dict>")
        fwrite("  </dict>")
        fwrite("  <key>SuppressBuildableAutocreation</key>")
        fwrite("  <dict></dict>")
        fwrite("</dict>")
        fwrite("</plist>")
    }

    return rootdir
}


private func open(path: String..., body: ((String) -> Void) -> Void) throws {
    var error: ErrorProtocol? = nil

    try Utility.fopen(Path.join(path), mode: .Write) { fp in
        body { line in
            if error == nil {
                do {
                    try fputs(line, fp)
                    try fputs("\n", fp)
                } catch let caught {
                    error = caught
                }
            }
        }
    }

    guard error == nil else { throw error! }
}
