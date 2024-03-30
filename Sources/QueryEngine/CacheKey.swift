//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_exported import protocol Crypto.HashFunction
import struct Foundation.URL
import struct SystemPackage.FilePath

/// Indicates that values of a conforming type can be hashed with an arbitrary hashing function. Unlike `Hashable`,
/// this protocol doesn't utilize random seed values and produces consistent hash values across process launches.
package protocol CacheKey: Encodable {
}

extension Bool: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    hashFunction.update(data: self ? [1] : [0])
  }
}

extension Int: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension Int8: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension Int16: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension Int32: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension Int64: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension UInt: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension UInt8: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension UInt16: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension UInt32: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension UInt64: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension Float: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension Double: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    withUnsafeBytes(of: self) {
      hashFunction.update(data: $0)
    }
  }
}

extension String: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    var t = String(reflecting: Self.self)
    t.withUTF8 {
      hashFunction.update(data: $0)
    }
    var x = self
    x.withUTF8 {
      hashFunction.update(data: $0)
    }
  }
}

extension FilePath: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    self.string.hash(with: &hashFunction)
  }
}

extension FilePath.Component: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    self.string.hash(with: &hashFunction)
  }
}

extension URL: CacheKey {
  func hash(with hashFunction: inout some HashFunction) {
    String(reflecting: Self.self).hash(with: &hashFunction)
    self.description.hash(with: &hashFunction)
  }
}
