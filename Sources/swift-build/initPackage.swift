/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Utility.Path
import func libc.fclose
import PackageType
import POSIX

func initPackage() throws {
    let rootd = try POSIX.getcwd()
    let pkgname = rootd.basename
    let manifest = Path.join(rootd, Manifest.filename)
    let gitignore = Path.join(rootd, ".gitignore")
    let sources = Path.join(rootd, "Sources")
    let tests = Path.join(rootd, "Tests")
    let main = Path.join(sources, "main.swift")
    
    guard !manifest.exists else {
        throw Error.ManifestAlreadyExists
    }
    
    let packageFP = try fopen(manifest, mode: .Write)
    defer {
        fclose(packageFP)
    }
    
    print("Creating \(Manifest.filename)")
    // print the manifest file
    try fputs("import PackageDescription\n", packageFP)
    try fputs("\n", packageFP)
    try fputs("let package = Package(\n", packageFP)
    try fputs("    name: \"\(pkgname)\"\n", packageFP)
    try fputs(")\n", packageFP)
    
    if !gitignore.exists {
        let gitignoreFP = try fopen(gitignore, mode: .Write)
        defer {
            fclose(gitignoreFP)
        }
        
        print("Creating .gitignore")
        // print the .gitignore
        try fputs(".DS_Store\n", gitignoreFP)
        try fputs("/.build\n", gitignoreFP)
        try fputs("/Packages\n", gitignoreFP)
    }
    
    if !sources.exists {
        print("Creating Sources/")
        try mkdir(sources)
        
        let mainFP = try fopen(main, mode: .Write)
        defer {
            fclose(mainFP)
        }
        print("Creating Sources/main.swift")
        try fputs("print(\"Hello, world!\")\n", mainFP)
    }
    
    if !tests.exists {
        print("Creating Tests/")
        try mkdir(tests)
    }
}
