// RUN: %empty-directory(%t)

// RUN: %swift-syntax-test --serialize-raw-tree --serialize-byte-tree --input-source-filename %s --output-filename %t/tree.bin
// RUN: %lit-test-helper -deserialize -serialization-format byteTree -pre-edit-tree %t/tree.bin -out %t/afterRoundtrip.swift
// RUN: diff -u %t/afterRoundtrip.swift %s

// RUN: %swift-syntax-test --serialize-raw-tree --serialize-byte-tree --input-source-filename %s --output-filename %t/tree_with_additional_fields.bin --add-bytetree-fields
// RUN: %lit-test-helper -deserialize -serialization-format byteTree -pre-edit-tree %t/tree_with_additional_fields.bin -out %t/afterRoundtripWithAdditionalFields.swift
// RUN: diff -u %t/afterRoundtripWithAdditionalFields.swift %s

func noArgs() {}
func oneArg(x: Int) {}
func oneUnlabeledArg(_ x: Int) {}

typealias FunctionAlias = (_ x: inout Int) -> Bool
typealias FunctionAliasNoLabel = (Int) -> Bool

func manyArgs(x: Int, y: Int, _ z: Bool, _ a: String) throws -> [Int] {
  return []
}

func rethrowing(_ f: (Bool) throws -> Int) rethrows -> Int {
  return try f(false)
}
