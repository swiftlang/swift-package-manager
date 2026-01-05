//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

@main
struct Exec {
  static func main() throws {
      let config = InstalledSwiftPMConfiguration(version: 1, swiftSyntaxVersionForMacroTemplate: .init(major: 509, minor: 0, patch: 0))
      let data = try JSONEncoder().encode(config)
      try data.write(to: URL(fileURLWithPath: "config.json"))
  }
}
