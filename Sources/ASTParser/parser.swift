/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

func parseASTString(astString: String, module: String) -> TestModule  {
    let sourceNodes = parseASTString(astString)
    var classes: [TestModule.Class] = []
    for source in sourceNodes {
        for node in source.nodes {
            guard case let .Class(isXCTestCaseSubClass) = node.type where isXCTestCaseSubClass else { continue }
            var testMethods: [String] = []
            for classNode in node.nodes {
                guard case let .Fn(signature) = classNode.type else { continue }
                if classNode.name.hasPrefix("test") && signature == "(\(node.name)) -> () -> ()" {
                    testMethods += [classNode.name]
                }
            }
            classes += [TestModule.Class(name: node.name, testMethods: testMethods)]
        }
    }
    return TestModule(name: module, classes: classes)
}


private class Node {
    enum NodeType {
        case Class(isXCTestCaseSubClass: Bool)
        case Fn(signature: String) // would be like : `(ClassName) -> () -> ()`
        case Unknown
    }
    var contents: String = "" {
        didSet {
            guard let index = contents.characters.indexOf(" ") else {
                return
            }
            let decl = contents[contents.startIndex..<index]
            name = contents.substringBetween("\"") ?? ""
            if decl == "class_decl" {
                type = .Class(isXCTestCaseSubClass: contents.hasSuffix("XCTestCase"))
            } else if decl == "func_decl", let signature = contents.substringBetween("'") {
                type = .Fn(signature: signature)
            }
        }
    }
    var nodes: [Node] = []
    var type: NodeType = .Unknown
    var name: String = ""
}

private func parseASTString(astString: String) -> [Node] {
    var stack = Array<Node>()
    var data = ""
    var quoteStarted = false
    var quoteChar: Character? = nil
    var sources: [Node] = []
    
    for char in astString.characters {

        if char == "(" && !quoteStarted {
            let node = Node()
            if data.characters.count > 0, let lastNode = stack.last, let chuzzledData = data.chuzzle() {
                lastNode.contents = chuzzledData
                if lastNode.contents == "source_file" { sources += [lastNode] }
            }
            stack.append(node)
            data = ""
        } else if char == ")" && !quoteStarted {
            if case let poppedNode = stack.removeLast() where stack.count > 0 {
                if data.characters.count > 0, let chuzzledData = data.chuzzle() {
                    poppedNode.contents = chuzzledData
                }
                stack.last!.nodes += [poppedNode]
               
            }
             data = ""
        } else {
            data = data + String(char)
            if char == "\"" || char == "'" {
                if quoteChar == nil { 
                    quoteChar = char
                    quoteStarted = true
                } else if char == quoteChar {
                    quoteChar = nil
                    quoteStarted = false
                }
             }       
        }
        
    }
    return sources
}

private extension String {
    func substringBetween(char: Character) -> String? {
        guard let firstIndex = self.characters.indexOf(char) where firstIndex != self.endIndex else {
            return nil
        }
        let choppedString = self[firstIndex.successor()..<self.endIndex]
        guard let secondIndex = choppedString.characters.indexOf(char) else { return nil }
        return choppedString[choppedString.startIndex..<secondIndex]
    }
}
