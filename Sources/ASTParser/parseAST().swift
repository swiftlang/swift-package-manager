/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility
import POSIX
import libc

public struct TestsClass {
    let module: String
    let name: String
    let testMethods: [String]
}

public func parseAST(dir: String) throws -> [TestsClass] {
    
    var classes: [TestsClass] = []
    
    try walk(dir, recursively: false).filter{ $0.isFile }.forEach { file in
        
        //FIXME: hacks
        func stringFromFILE(filePtr: UnsafeMutablePointer<FILE>) -> String {
            guard filePtr != nil else {
                return ""
            }
            let buffer = [CChar](count: 1024, repeatedValue: 0)
            var string = String()
            while libc.fgets(UnsafeMutablePointer(buffer), Int32(buffer.count), filePtr) != nil {
                if let read = String.fromCString(buffer) {
                    string += read
                }
            }
            return string
        }
        let fp = try fopen(file)
        defer { fclose(fp) }
        let basename = file.basename
        let fname = basename[basename.startIndex..<basename.endIndex.advancedBy(-4)]
        print("Processing \(fname) AST")
        classes += parseASTString(stringFromFILE(fp), module: fname)
    }
    return classes
}

func parseASTString(astString: String, module: String) -> [TestsClass] {
    
    var stack = Array<Node>()
    
    var data = ""
    var quoteStarted: Bool = false
    var assignmentStarted: Bool = false
    
    var sources: [Node] = []
    
    for index in astString.characters.startIndex..<astString.characters.endIndex {
        
        let char = astString.characters[index]
        
        func peekNext() -> String {
            return "\(astString.characters[index.successor()])"
        }
        
        if char == "(" && !(quoteStarted || assignmentStarted) {
            let node = Node()
            if data.chuzzle()?.characters.count > 0, let lastNode = stack.last {
                lastNode.contents = data.chuzzle()!
                if lastNode.contents == "source_file" {
                    sources += [lastNode]
                }
            }
            stack.append(node)
            data = ""
        } else if char == ")" && !(quoteStarted || assignmentStarted) {
            var poppedNode: Node?
            if stack.count > 0 {
                poppedNode = stack.removeLast()
                if data.chuzzle()?.characters.count > 0, let poppedNode = poppedNode {
                    poppedNode.contents = data.chuzzle()!
                }
                data = ""
            }
            if let last = stack.last, let poppedNode = poppedNode {
                last.nodes += [poppedNode]
            }
        } else {
            data = data + String(char)
            if char == "\""  || char == "'" {
                quoteStarted = !quoteStarted
                if quoteStarted { assignmentStarted = false } //Hack
            }
            // else if char == "=" {
            //             assignmentStarted = true
            //         }
            //         else if assignmentStarted && (char == " " || (char == ")" && peekNext() == ")")) {
            //             assignmentStarted = false
            //         }
            
        }
    }
    
    
    var classes: [TestsClass] = []
     for source in sources {
     	for node in source.nodes where node.type == .Class {
            var methods: [String] = []
             for classNode in node.nodes where classNode.type == .Fn {
                 methods.append(classNode.name)
             }
            classes.append(TestsClass(module: module, name: node.name, testMethods: methods))
         }
     }
    
    return classes
}

enum Type: String {
    case Class = "class_decl"
    case Fn = "func_decl"
    case Unknown = ""
}

class Node: CustomStringConvertible {
    
    var contents: String = ""
    var nodes: [Node] = []
    
    init() {
    }
    
    var description: String {
        if nodes.count > 0 {
            return "\(contents) \(nodes)"
        }
        return "\(contents)"
    }
    
    var type: Type {
        if contents.hasPrefix(Type.Class.rawValue) {
            return .Class
        }
        if contents.hasPrefix(Type.Fn.rawValue) {
            return .Fn
        }
        return .Unknown
    }
    
    var name: String {
        switch type {
        case .Class: fallthrough
        case .Fn:
            var str = ""
            
            var quoteBegan: Bool = false
            for char in self.contents.characters {
                if char == "\"" {
                    if quoteBegan { return str[str.startIndex.successor()..<str.endIndex] }
                    quoteBegan = true
                }
                if quoteBegan { str += "\(char)" }
            }
            
            return str
        default:
            return ""
        }
    }
}