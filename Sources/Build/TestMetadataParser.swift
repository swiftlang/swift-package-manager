/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Utility
import PackageType

struct TestClassMetadata {
    let name: String
    let testNames: [String]
}

struct ModuleTestMetadata {
    let module: TestModule
    let testManifestPath: String
    let dependencies: [String]
    let classes: [TestClassMetadata]
}

protocol TestMetadataParser {
    func parseTestClasses(testFilePath: String) throws -> [TestClassMetadata]?
}

//up for grabs
//struct ASTTestMetadataParser: TestMetadataParser {
//    
//
//}

struct StringTestMetadataParser: TestMetadataParser {
    
    /// Based on the absolute path passed in parses test class metadata
    /// Returns array because there might be more test classes in one file
    func parseTestClasses(testFilePath: String) throws -> [TestClassMetadata]? {
        
        guard let lines = try? File(path: testFilePath).enumerate() else { return nil }
        
        var classes = [TestClassMetadata]()
        
        //parse lines one by one, no need to load the whole into memory
        var outLine: String? = lines.next()
        CLASSES: while true {
            
            guard let line = outLine else {
                //EOF, no more classes
                return classes.nilIfEmpty()
            }
            
            //look for a class name
            if let className = parseClassName(line) {
                //found class name, start searching for test names
                
                var testNames = [String]()
                while true {
                    
                    guard let line = lines.next() else {
                        //EOF, finish & add current class
                        if testNames.count > 0 {
                            let testClass = TestClassMetadata(name: className, testNames: testNames)
                            classes.append(testClass)
                        }
                        return classes.nilIfEmpty()
                    }
                    
                    if let testName = parseTestName(line) {
                        //found another test name
                        testNames.append(testName)
                    }
                    
                    if let _ = parseClassName(line) {
                        continue CLASSES
                    }
                }
            }
            
            outLine = lines.next()
        }
    }
    
    func parseClassName(line: String) -> String? {
        var comps = line.splitWithCharactersInString(":\r\t\n ").filter { !$0.isEmpty }
        guard comps.count >= 2 else { return nil }
        //see if this line is a candidate
        guard Set(comps).contains("class") else { return nil }
        while true {
            let allowedFirst = Set(["private", "public", "internal", "final"])
            if allowedFirst.contains(comps[0]) {
                //drop first
                comps = Array(comps.dropFirst())
            } else {
                break
            }
        }
        guard comps[0] == "class" else { return nil }
        guard comps[2] == "XCTestCase" else { return nil }
        return comps[1]
    }
    
    func parseTestName(line: String) -> String? {
        let comps = line.splitWithCharactersInString(" \t\n\r").filter { !$0.isEmpty }
        guard comps.count >= 2 else { return nil }
        guard comps[0] == "func" else { return nil }
        guard comps[1].hasPrefix("test") else { return nil }
        //remove trailing parentheses
        return String(comps[1].characters.dropLast(2))
    }
}




