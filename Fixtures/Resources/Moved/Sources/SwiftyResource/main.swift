import Foundation

let bundle = Bundle.module

let foo = bundle.path(forResource: "foo", ofType: "txt")!
let contents = FileManager.default.contents(atPath: foo)!
print(String(data: contents, encoding: .utf8)!, terminator: "")
