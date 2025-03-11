//===--------------- Triple.swift - Swift Target Triples ------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//
// Warning: This file has been copied with minimal modifications from
// swift-driver to avoid a direct dependency. See Vendor/README.md for details.
//
// Changes:
// - Replaced usage of `\(_:or:)` string interpolation.
// - Replaced usage of `self.isDarwin` with `self.os?.isDarwin ?? false`.
//
//===----------------------------------------------------------------------===//

/// Helper for working with target triples.
///
/// Target triples are strings in the canonical form:
///   ARCHITECTURE-VENDOR-OPERATING_SYSTEM
/// or
///   ARCHITECTURE-VENDOR-OPERATING_SYSTEM-ENVIRONMENT
///
/// This type is used for clients which want to support arbitrary
/// configuration names, but also want to implement certain special
/// behavior for particular configurations. This class isolates the mapping
/// from the components of the configuration name to well known IDs.
///
/// At its core the Triple class is designed to be a wrapper for a triple
/// string; the constructor does not change or normalize the triple string.
/// Clients that need to handle the non-canonical triples that users often
/// specify should use the normalize method.
///
/// See autoconf/config.guess for a glimpse into what target triples
/// look like in practice.
///
/// This is a port of https://github.com/apple/swift-llvm/blob/stable/include/llvm/ADT/Triple.h
@dynamicMemberLookup
public struct Triple: Sendable {
  /// `Triple` proxies predicates from `Triple.OS`, returning `false` for an unknown OS.
  public subscript(dynamicMember predicate: KeyPath<OS, Bool>) -> Bool {
    os?[keyPath: predicate] ?? false
  }

  /// The original triple string.
  public let triple: String

  /// The parsed arch.
  public let arch: Arch?

  /// The parsed subarchitecture.
  public let subArch: SubArch?

  /// The parsed vendor.
  public let vendor: Vendor?

  /// The parsed OS.
  public let os: OS?

  /// The parsed Environment type.
  public let environment: Environment?

  /// The object format type.
  public let objectFormat: ObjectFormat?

  /// Represents a version that may be present in the target triple.
    public struct Version: Equatable, Comparable, CustomStringConvertible, Sendable {
    public static let zero = Version(0, 0, 0)

    public var major: Int
    public var minor: Int
    public var micro: Int

    public init<S: StringProtocol>(parse string: S) {
      let components = string.split(separator: ".", maxSplits: 3).map{ Int($0) ?? 0 }
      self.major = components.count > 0 ? components[0] : 0
      self.minor = components.count > 1 ? components[1] : 0
      self.micro = components.count > 2 ? components[2] : 0
    }

    public init(_ major: Int, _ minor: Int, _ micro: Int) {
      self.major = major
      self.minor = minor
      self.micro = micro
    }

    public static func <(lhs: Version, rhs: Version) -> Bool {
      return (lhs.major, lhs.minor, lhs.micro) < (rhs.major, rhs.minor, rhs.micro)
    }

    public var description: String {
      return "\(major).\(minor).\(micro)"
    }
  }

  public init(_ string: String, normalizing: Bool = false) {
    var parser = TripleParser(string, allowMore: normalizing)

    // First, see if each component parses at its expected position.
    var parsedArch = parser.match(ArchInfo.self, at: 0)
    var parsedVendor = parser.match(Vendor.self, at: 1)
    var parsedOS = parser.match(OS.self, at: 2)
    var parsedEnv = parser.match(EnvInfo.self, at: 3)

    if normalizing {
      // Next, try to fill in each unmatched field from the rejected components.
      parser.rematch(&parsedArch, at: 0)
      parser.rematch(&parsedVendor, at: 1)
      parser.rematch(&parsedOS, at: 2)
      parser.rematch(&parsedEnv, at: 3)

      let isCygwin = parser.componentsIndicateCygwin
      let isMinGW32 = parser.componentsIndicateMinGW32

      if
      let parsedEnv = parsedEnv,
      parsedEnv.value.environment == .android,
      parsedEnv.substring.hasPrefix("androideabi") {
        let androidVersion = parsedEnv.substring.dropFirst("androideabi".count)

        parser.components[3] = "android\(androidVersion)"
      }

      // SUSE uses "gnueabi" to mean "gnueabihf"
      if parsedVendor?.value == .suse && parsedEnv?.value.environment == .gnueabi {
        parser.components[3] = "gnueabihf"
      }

      if parsedOS?.value == .win32 {
        parser.components.resize(toCount: 4, paddingWith: "")
        parser.components[2] = "windows"
        if parsedEnv?.value.environment == nil {
          if let objectFormat = parsedEnv?.value.objectFormat, objectFormat != .coff {
            parser.components[3] = Substring(objectFormat.name)
          } else {
            parser.components[3] = "msvc"
          }
        }
      } else if isMinGW32 {
        parser.components.resize(toCount: 4, paddingWith: "")
        parser.components[2] = "windows"
        parser.components[3] = "gnu"
      } else if isCygwin {
        parser.components.resize(toCount: 4, paddingWith: "")
        parser.components[2] = "windows"
        parser.components[3] = "cygnus"
      }

      if isMinGW32 || isCygwin || (parsedOS?.value == .win32 && parsedEnv?.value.environment != nil) {
        if let objectFormat = parsedEnv?.value.objectFormat, objectFormat != .coff {
          parser.components.resize(toCount: 5, paddingWith: "")
          parser.components[4] = Substring(objectFormat.name)
        }
      }

      // Now that we've parsed everything, we construct a normalized form of the
      // triple string.
      triple = parser.components.map({ $0.isEmpty ? "unknown" : $0 }).joined(separator: "-")
    }
    else {
      triple = string
    }

    // Unpack the parsed data into the fields. If no environment info was found,
    // attempt to infer it from other fields.
    self.arch = parsedArch?.value.arch
    self.subArch = parsedArch?.value.subArch
    self.vendor = parsedVendor?.value
    self.os = parsedOS?.value

    if let parsedEnv = parsedEnv {
      self.environment = parsedEnv.value.environment
      self.objectFormat = parsedEnv.value.objectFormat
        ?? ObjectFormat.infer(arch: parsedArch?.value.arch,
                              os: parsedOS?.value)
    }
    else {
      self.environment = Environment.infer(archName: parsedArch?.substring)
      self.objectFormat = ObjectFormat.infer(arch: parsedArch?.value.arch,
                                             os: parsedOS?.value)
    }
  }
}

extension Triple: Codable {
  public init(from decoder: Decoder) throws {
    self.init(try decoder.singleValueContainer().decode(String.self), normalizing: false)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(triple)
  }
}

// MARK: - Triple component parsing

fileprivate protocol TripleComponent {
  static func parse(_ component: Substring) -> Self?

  static func valueIsValid(_ value: Substring) -> Bool
}

extension TripleComponent {
  static func valueIsValid(_ value: Substring) -> Bool {
    parse(value) != nil
  }
}

fileprivate struct ParsedComponent<Value: TripleComponent> {
  let value: Value
  let substring: Substring

  /// Attempts to parse `component` with `parser`, placing it in `rejects` if
  /// it does not succeed.
  ///
  /// - Returns: `nil` if `type` cannot parse `component`; otherwise, an
  ///   instance containing the component and its parsed value.
  init?(_ component: Substring, as type: Value.Type) {
    guard let value = type.parse(component) else {
      return nil
    }

    self.value = value
    self.substring = component
  }
}

/// Holds the list of components in this string, as well as whether or not we
/// have matched them.
///
/// In normalizing mode, the triple is parsed in two steps:
///
/// 1. Try to match each component against the type of component expected in
///    that position. (`TripleParser.match(_:at:)`.)
/// 2. For each type of component we have not yet matched, try each component
///    we have not yet found a match for, moving the match (if found) to the
///    correct location. (`TripleParser.rematch(_:at:)`.)
///
/// In non-normalizing mode, we simply skip the second step.
fileprivate struct TripleParser {
  var components: [Substring]
  var isMatched: Set<Int> = []

  var componentsIndicateCygwin: Bool {
    components.count > 2 ? components[2].hasPrefix("cygwin") : false
  }

  var componentsIndicateMinGW32: Bool {
    components.count > 2 ? components[2].hasPrefix("mingw") : false
  }

  init(_ string: String, allowMore: Bool) {
    components = string.split(
      separator: "-", maxSplits: allowMore ? Int.max : 3,
      omittingEmptySubsequences: false
    )
  }

  /// Attempt to parse the component at position `i` as a `Value`, marking it as
  /// matched if successful.
  mutating func match<Value: TripleComponent>(_: Value.Type, at i: Int)
    -> ParsedComponent<Value>?
  {
    guard
      i < components.endIndex,
      let parsed = ParsedComponent(components[i], as: Value.self)
    else {
      return nil
    }

    precondition(!isMatched.contains(i))
    isMatched.insert(i)

    return parsed
  }

  /// If `value` has not been filled in, attempt to parse all unmatched
  /// components with it, correcting the components list if a match is found.
  mutating func rematch<Value: TripleComponent>(
    _ value: inout ParsedComponent<Value>?, at correctIndex: Int
  ) {
    guard value == nil else { return }

    precondition(!isMatched.contains(correctIndex),
                 "Lost the parsed component somehow?")

    for i in unmatchedIndices {
      guard Value.valueIsValid(components[i]) else {
        continue
      }

      value = ParsedComponent(components[i], as: Value.self)
      shiftComponent(at: i, to: correctIndex)
      isMatched.insert(correctIndex)

      return
    }
  }

  /// Returns `component.indices` with matched elements lazily filtered out.
  private var unmatchedIndices: LazyFilterSequence<Range<Int>> {
    components.indices.lazy.filter { [isMatched] in
      !isMatched.contains($0)
    }
  }

  /// Rearrange `components` so that the element at `actualIndex` now appears
  /// at `correctIndex`, without moving any components that have already
  /// matched.
  ///
  /// The exact transformations performed by this function are difficult to
  /// describe concisely, but they work well in practice for the ways people
  /// tend to permute triples. Essentially:
  ///
  /// * If a component appears later than it ought to, it is moved to the right
  ///   location and other unmatched components are shifted later.
  /// * If a component appears earlier than it ought to, empty components are
  ///   either found later in the list and moved before it, or created from
  ///   whole cloth and inserted before it.
  /// * If no movement is necessary, this is a no-op.
  ///
  /// - Parameter actualIndex: The index that the component is currently at.
  /// - Parameter correctIndex: The index that the component ought to be at.
  ///
  /// - Precondition: Neither `correctIndex` nor `actualIndex` are matched.
  private mutating func shiftComponent(
    at actualIndex: Int,
    to correctIndex: Int
  ) {
    // Don't mark actualIndex as matched until after you've called this method.
    precondition(!isMatched.contains(actualIndex),
                 "actualIndex was already matched to something else?")
    precondition(!isMatched.contains(correctIndex),
                 "correctIndex already had something match it?")

    if correctIndex < actualIndex {
      // Repeatedly swap `actualIndex` with its leftward neighbor, skipping
      // matched components, until it finds its way to `correctIndex`.

      // Compute all of the indices that we'll shift, not including any that
      // have matched, and then build a reversed list of adjacent pairs. (That
      // is, if the filter returns `[1,2,4]`, the resulting list will be
      // `[(4,2),(2,1)]`.)
      let swaps = unmatchedIndices[correctIndex...actualIndex]
          .zippedPairs().reversed()

      // Swap each pair. This has the effect of moving `actualIndex` to
      // `correctIndex` and shifting each unmatched element between them to
      // take up the space. Swapping instead of assigning ought to avoid retain
      // count traffic.
      for (earlier, later) in swaps {
        components.swapAt(earlier, later)
      }
    }

    // The rest of this method is concerned with shifting components rightward.
    // If we don't need to do that, we're done.
    guard correctIndex > actualIndex else { return }

    // We will essentially insert one empty component in front of `actualIndex`,
    // then recurse to shift `actualIndex + 1` if necessary. However, we want to
    // avoid shifting matched components and eat empty components, so this is
    // all a bit more complicated than just that.

    // Create a new empty component. We call it `removed` because for most
    // of this variable's lifetime, `removed` is a component that has been
    // removed from the list.
    var removed: Substring = ""

    // This loop has the effect of inserting the empty component and
    // shifting other unmatched components rightward until we either remove
    // an empty unmatched component, or remove the last element of the list.
    for i in unmatchedIndices[actualIndex...] {
      swap(&removed, &components[i])

      // If the element we removed is empty, consume it rather than reinserting
      // it later in the list.
      if removed.isEmpty { break }
    }

    // If we shifted a non-empty component off the end, add it back in.
    if !removed.isEmpty {
      components.append(removed)
    }

    // Find the next unmatched index after `actualIndex`; that's where we moved
    // the element at `actualIndex` to.
    let nextIndex = unmatchedIndices[(actualIndex + 1)..<correctIndex].first ??
        correctIndex

    // Recurse to move or create another empty component if necessary.
    shiftComponent(at: nextIndex, to: correctIndex)
  }
}

extension Collection {
  fileprivate func zippedPairs() -> Zip2Sequence<SubSequence, SubSequence> {
    zip(dropLast(), dropFirst())
  }
}

// MARK: - Parse Arch

extension Triple {
  fileprivate struct ArchInfo: TripleComponent {
    var arch: Triple.Arch
    var subArch: Triple.SubArch?

    fileprivate static func parse(_ component: Substring) -> ArchInfo? {
      // This code assumes that all architectures with a subarch also have an arch.
      // This is slightly different from llvm::Triple, whose
      // startswith/endswith-based logic might occasionally recognize a subarch
      // without an arch, e.g. "xxkalimba5" would have an unknown arch and a
      // kalimbav5 subarch. I'm pretty sure that's undesired behavior from LLVM.

      guard let arch = Triple.Arch.parse(component) else { return nil }
      return ArchInfo(arch: arch, subArch: Triple.SubArch.parse(component))
    }
  }

public enum Arch: String, CaseIterable, Decodable, Sendable {
    /// ARM (little endian): arm, armv.*, xscale
    case arm
    // ARM (big endian): armeb
    case armeb
    /// AArch64 (little endian): aarch64
    case aarch64
    /// AArch64e (little endian): aarch64e
    case aarch64e
    /// AArch64 (big endian): aarch64_be
    case aarch64_be
    // AArch64 (little endian) ILP32: aarch64_32
    case aarch64_32
    /// ARC: Synopsis ARC
    case arc
    /// AVR: Atmel AVR microcontroller
    case avr
    /// eBPF or extended BPF or 64-bit BPF (little endian)
    case bpfel
    /// eBPF or extended BPF or 64-bit BPF (big endian)
    case bpfeb
    /// Hexagon: hexagon
    case hexagon
    /// MIPS: mips, mipsallegrex, mipsr6
    case mips
    /// MIPSEL: mipsel, mipsallegrexe, mipsr6el
    case mipsel
    // MIPS64: mips64, mips64r6, mipsn32, mipsn32r6
    case mips64
    // MIPS64EL: mips64el, mips64r6el, mipsn32el, mipsn32r6el
    case mips64el
    // MSP430: msp430
    case msp430
    // PPC: powerpc
    case ppc
    // PPC64: powerpc64, ppu
    case ppc64
    // PPC64LE: powerpc64le
    case ppc64le
    // R600: AMD GPUs HD2XXX - HD6XXX
    case r600
    // AMDGCN: AMD GCN GPUs
    case amdgcn
    // RISC-V (32-bit): riscv32
    case riscv32
    // RISC-V (64-bit): riscv64
    case riscv64
    // Sparc: sparc
    case sparc
    // Sparcv9: Sparcv9
    case sparcv9
    // Sparc: (endianness = little). NB: 'Sparcle' is a CPU variant
    case sparcel
    // SystemZ: s390x
    case systemz
    // TCE (http://tce.cs.tut.fi/): tce
    case tce
    // TCE little endian (http://tce.cs.tut.fi/): tcele
    case tcele
    // Thumb (little endian): thumb, thumbv.*
    case thumb
    // Thumb (big endian): thumbeb
    case thumbeb
    // X86: i[3-9]86
    case x86 = "i386"
    // X86-64: amd64, x86_64
    case x86_64
    // XCore: xcore
    case xcore
    // NVPTX: 32-bit
    case nvptx
    // NVPTX: 64-bit
    case nvptx64
    // le32: generic little-endian 32-bit CPU (PNaCl)
    case le32
    // le64: generic little-endian 64-bit CPU (PNaCl)
    case le64
    // AMDIL
    case amdil
    // AMDIL with 64-bit pointers
    case amdil64
    // AMD HSAIL
    case hsail
    // AMD HSAIL with 64-bit pointers
    case hsail64
    // SPIR: standard portable IR for OpenCL 32-bit version
    case spir
    // SPIR: standard portable IR for OpenCL 64-bit version
    case spir64
    // Kalimba: generic kalimba
    case kalimba
    // SHAVE: Movidius vector VLIW processors
    case shave
    // Lanai: Lanai 32-bit
    case lanai
    // WebAssembly with 32-bit pointers
    case wasm32
    // WebAssembly with 64-bit pointers
    case wasm64
    // 32-bit RenderScript
    case renderscript32
    // 64-bit RenderScript
    case renderscript64

    static func parse(_ archName: Substring) -> Triple.Arch? {
      switch archName {
      case "i386", "i486", "i586", "i686":
        return .x86
      case "i786", "i886", "i986":
        return .x86
      case "amd64", "x86_64", "x86_64h":
        return .x86_64
      case "powerpc", "ppc", "ppc32":
        return .ppc
      case "powerpc64", "ppu", "ppc64":
        return .ppc64
      case "powerpc64le", "ppc64le":
        return .ppc64le
      case "xscale":
        return .arm
      case "xscaleeb":
        return .armeb
      case "aarch64":
        return .aarch64
      case "aarch64_be":
        return .aarch64_be
      case "aarch64_32":
        return .aarch64_32
      case "arc":
        return .arc
      case "arm64":
        return .aarch64
      case "arm64e":
        return .aarch64e
      case "arm64_32":
        return .aarch64_32
      case "arm":
        return .arm
      case "armeb":
        return .armeb
      case "thumb":
        return .thumb
      case "thumbeb":
        return .thumbeb
      case "avr":
        return .avr
      case "msp430":
        return .msp430
      case "mips", "mipseb", "mipsallegrex", "mipsisa32r6", "mipsr6":
        return .mips
      case "mipsel", "mipsallegrexel", "mipsisa32r6el", "mipsr6el":
        return .mipsel
      case "mips64", "mips64eb", "mipsn32", "mipsisa64r6", "mips64r6", "mipsn32r6":
        return .mips64
      case "mips64el", "mipsn32el", "mipsisa64r6el", "mips64r6el", "mipsn32r6el":
        return .mips64el
      case "r600":
        return .r600
      case "amdgcn":
        return .amdgcn
      case "riscv32":
        return .riscv32
      case "riscv64":
        return .riscv64
      case "hexagon":
        return .hexagon
      case "s390x", "systemz":
        return .systemz
      case "sparc":
        return .sparc
      case "sparcel":
        return .sparcel
      case "sparcv9", "sparc64":
        return .sparcv9
      case "tce":
        return .tce
      case "tcele":
        return .tcele
      case "xcore":
        return .xcore
      case "nvptx":
        return .nvptx
      case "nvptx64":
        return .nvptx64
      case "le32":
        return .le32
      case "le64":
        return .le64
      case "amdil":
        return .amdil
      case "amdil64":
        return .amdil64
      case "hsail":
        return .hsail
      case "hsail64":
        return .hsail64
      case "spir":
        return .spir
      case "spir64":
        return .spir64
      case _ where archName.hasPrefix("kalimba"):
        return .kalimba
      case "lanai":
        return .lanai
      case "shave":
        return .shave
      case "wasm32":
        return .wasm32
      case "wasm64":
        return .wasm64
      case "renderscript32":
        return .renderscript32
      case "renderscript64":
        return .renderscript64

      case _ where archName.hasPrefix("arm") || archName.hasPrefix("thumb") || archName.hasPrefix("aarch64"):
        return parseARMArch(archName)

      case _ where archName.hasPrefix("bpf"):
        return parseBPFArch(archName)

      default:
        return nil
      }
    }

    enum Endianness {
      case big, little

      // Based on LLVM's ARM::parseArchEndian
      init?<S: StringProtocol>(armArchName archName: S) {
        if archName.starts(with: "armeb") || archName.starts(with: "thumbeb") || archName.starts(with: "aarch64_be") {
          self = .big
        } else if archName.starts(with: "arm") || archName.starts(with: "thumb") {
          self = archName.hasSuffix("eb") ? .big : .little
        } else if archName.starts(with: "aarch64") || archName.starts(with: "aarch64_32") {
          self = .little
        } else {
          return nil
        }
      }
    }

    enum ARMISA {
      case aarch64, thumb, arm

      // Based on LLVM's ARM::parseArchISA
      init?<S: StringProtocol>(archName: S) {
        if archName.starts(with: "aarch64") || archName.starts(with: "arm64") {
          self = .aarch64
        } else if archName.starts(with: "thumb") {
          self = .thumb
        } else if archName.starts(with: "arm") {
          self = .arm
        } else {
          return nil
        }
      }
    }

    // Parse ARM architectures not handled by `parse`. On its own, this is not
    // enough to correctly parse an ARM architecture.
    private static func parseARMArch<S: StringProtocol>(_ archName: S) -> Triple.Arch? {

      let ISA = ARMISA(archName: archName)
      let endianness = Endianness(armArchName: archName)

      let arch: Triple.Arch?
      switch (endianness, ISA) {
      case (.little, .arm):
        arch = .arm
      case (.little, .thumb):
        arch = .thumb
      case (.little, .aarch64):
        arch = .aarch64
      case (.big, .arm):
        arch = .armeb
      case (.big, .thumb):
        arch = .thumbeb
      case (.big, .aarch64):
        arch = .aarch64_be
      case (nil, _), (_, nil):
        arch = nil
      }

      let cannonicalArchName = cannonicalARMArchName(from: archName)

      if cannonicalArchName.isEmpty {
        return nil
      }

      // Thumb only exists in v4+
      if ISA == .thumb && (cannonicalArchName.hasPrefix("v2") || cannonicalArchName.hasPrefix("v3")) {
          return nil
      }

      // Thumb only for v6m
      if case .arm(let subArch) = Triple.SubArch.parse(archName), subArch.profile == .m && subArch.version == 6 {
        if endianness == .big {
          return .thumbeb
        } else {
          return .thumb
        }
      }

      return arch
    }

    // Based on LLVM's ARM::getCanonicalArchName
    //
    // MArch is expected to be of the form (arm|thumb)?(eb)?(v.+)?(eb)?, but
    // (iwmmxt|xscale)(eb)? is also permitted. If the former, return
    // "v.+", if the latter, return unmodified string, minus 'eb'.
    // If invalid, return empty string.
    fileprivate static func cannonicalARMArchName<S: StringProtocol>(from arch: S) -> String {
      var name = Substring(arch)

      func dropPrefix(_ prefix: String) {
        if name.hasPrefix(prefix) {
          name = name.dropFirst(prefix.count)
        }
      }

      let possiblePrefixes = ["arm64_32", "arm64", "aarch64_32", "arm", "thumb", "aarch64"]

      if let prefix = possiblePrefixes.first(where: name.hasPrefix) {
        dropPrefix(prefix)

        if prefix == "aarch64" {
          // AArch64 uses "_be", not "eb" suffix.
          if name.contains("eb") {
            return ""
          }

          dropPrefix("_be")
        }
      }

      // Ex. "armebv7", move past the "eb".
      if name != arch {
        dropPrefix("eb")
      }
      // Or, if it ends with eb ("armv7eb"), chop it off.
      else if name.hasSuffix("eb") {
        name = name.dropLast(2)
      }

      // Reached the end - arch is valid.
      if name.isEmpty {
        return String(arch)
      }

      // Only match non-marketing names
      if name != arch {
        // Must start with 'vN'.
        if name.count >= 2 && (name.first != "v" || !name.dropFirst().first!.isNumber) {
          return ""
        }

        // Can't have an extra 'eb'.
        if name.hasPrefix("eb") {
          return ""
        }
      }

      // Arch will either be a 'v' name (v7a) or a marketing name (xscale).
      return String(name)
    }

    private static func parseBPFArch<S: StringProtocol>(_ archName: S) -> Triple.Arch? {

      let isLittleEndianHost = 1.littleEndian == 1

      switch archName {
      case "bpf":
        return isLittleEndianHost ? .bpfel : .bpfeb
      case "bpf_be", "bpfeb":
        return .bpfeb
      case "bpf_le", "bpfel":
        return .bpfel
      default:
        return nil
      }
    }

    /// Whether or not this architecture has 64-bit pointers
    public var is64Bit: Bool { pointerBitWidth == 64 }

    /// Whether or not this architecture has 32-bit pointers
    public var is32Bit: Bool { pointerBitWidth == 32 }

    /// Whether or not this architecture has 16-bit pointers
    public var is16Bit: Bool { pointerBitWidth == 16 }

    /// The width in bits of pointers on this architecture.
    var pointerBitWidth: Int {
      switch self {
      case .avr, .msp430:
        return 16

      case .arc, .arm, .armeb, .hexagon, .le32, .mips, .mipsel, .nvptx,
           .ppc, .r600, .riscv32, .sparc, .sparcel, .tce, .tcele, .thumb,
           .thumbeb, .x86, .xcore, .amdil, .hsail, .spir, .kalimba,.lanai,
           .shave, .wasm32, .renderscript32, .aarch64_32:
        return 32

      case .aarch64, .aarch64e, .aarch64_be, .amdgcn, .bpfel, .bpfeb, .le64, .mips64,
           .mips64el, .nvptx64, .ppc64, .ppc64le, .riscv64, .sparcv9, .systemz,
           .x86_64, .amdil64, .hsail64, .spir64,  .wasm64, .renderscript64:
        return 64
      }
    }
  }
}

// MARK: - Parse SubArch

extension Triple {
    public enum SubArch: Hashable, Sendable {

    public enum ARM: Sendable {

      public enum Profile {
        case a, r, m
      }

      case v2
      case v2a
      case v3
      case v3m
      case v4
      case v4t
      case v5
      case v5e
      case v6
      case v6k
      case v6kz
      case v6m
      case v6t2
      case v7
      case v7em
      case v7k
      case v7m
      case v7r
      case v7s
      case v7ve
      case v8
      case v8_1a
      case v8_1m_mainline
      case v8_2a
      case v8_3a
      case v8_4a
      case v8_5a
      case v8m_baseline
      case v8m_mainline
      case v8r

      var profile: Triple.SubArch.ARM.Profile? {
        switch self {
        case .v6m, .v7m, .v7em, .v8m_mainline, .v8m_baseline, .v8_1m_mainline:
          return .m
        case .v7r, .v8r:
          return .r
        case .v7, .v7ve, .v7k, .v8, .v8_1a, .v8_2a, .v8_3a, .v8_4a, .v8_5a:
          return .a
        case .v2, .v2a, .v3, .v3m, .v4, .v4t, .v5, .v5e, .v6, .v6k, .v6kz, .v6t2, .v7s:
          return nil
        }
      }

      var version: Int {
        switch self {
        case .v2, .v2a:
          return 2
        case .v3, .v3m:
          return 3
        case .v4, .v4t:
          return 4
        case .v5, .v5e:
          return 5
        case .v6, .v6k, .v6kz, .v6m, .v6t2:
          return 6
        case .v7, .v7em, .v7k, .v7m, .v7r, .v7s, .v7ve:
          return 7
        case .v8, .v8_1a, .v8_1m_mainline, .v8_2a, .v8_3a, .v8_4a, .v8_5a, .v8m_baseline, .v8m_mainline, .v8r:
          return 8
        }
      }
    }

    public enum Kalimba: Sendable {
      case v3
      case v4
      case v5
    }

    public enum MIPS: Sendable {
      case r6
    }

    case arm(ARM)
    case kalimba(Kalimba)
    case mips(MIPS)

    fileprivate static func parse<S: StringProtocol>(_ component: S) -> Triple.SubArch? {

      if component.hasPrefix("mips") && (component.hasSuffix("r6el") || component.hasSuffix("r6")) {
        return .mips(.r6)
      }

      let armSubArch = Triple.Arch.cannonicalARMArchName(from: component)

      if armSubArch.isEmpty {
        switch component {
        case _ where component.hasSuffix("kalimba3"):
          return .kalimba(.v3)
        case _ where component.hasSuffix("kalimba4"):
          return .kalimba(.v4)
        case _ where component.hasSuffix("kalimba5"):
          return .kalimba(.v5)
        default:
          return nil
        }
      }

      switch armSubArch {
      case "v2":
        return .arm(.v2)
      case "v2a":
        return .arm(.v2a)
      case "v3":
        return .arm(.v3)
      case "v3m":
        return .arm(.v3m)
      case "v4":
        return .arm(.v4)
      case "v4t":
        return .arm(.v4t)
      case "v5t":
        return .arm(.v5)
      case "v5te", "v5tej", "xscale":
        return .arm(.v5e)
      case "v6":
        return .arm(.v6)
      case "v6k":
        return .arm(.v6k)
      case "v6kz":
        return .arm(.v6kz)
      case "v6m", "v6-m":
        return .arm(.v6m)
      case "v6t2":
        return .arm(.v6t2)
      case "v7a", "v7-a":
        return .arm(.v7)
      case "v7k":
        return .arm(.v7k)
      case "v7m", "v7-m":
        return .arm(.v7m)
      case "v7em", "v7e-m":
        return .arm(.v7em)
      case "v7r", "v7-r":
        return .arm(.v7r)
      case "v7s":
        return .arm(.v7s)
      case "v7ve":
        return .arm(.v7ve)
      case "v8-a":
        return .arm(.v8)
      case "v8-m.main":
        return .arm(.v8m_mainline)
      case "v8-m.base":
        return .arm(.v8m_baseline)
      case "v8-r":
        return .arm(.v8r)
      case "v8.1-m.main":
        return .arm(.v8_1m_mainline)
      case "v8.1-a":
        return .arm(.v8_1a)
      case "v8.2-a":
        return .arm(.v8_2a)
      case "v8.3-a":
        return .arm(.v8_3a)
      case "v8.4-a":
        return .arm(.v8_4a)
      case "v8.5-a":
        return .arm(.v8_5a)
      default:
        return nil
      }
    }
  }
}

// MARK: - Parse Vendor

extension Triple {
    public enum Vendor: String, CaseIterable, TripleComponent, Sendable {
    case apple
    case pc
    case scei
    case bgp
    case bgq
    case freescale = "fsl"
    case ibm
    case imaginationTechnologies = "img"
    case mipsTechnologies = "mti"
    case nvidia
    case csr
    case myriad
    case amd
    case mesa
    case suse
    case openEmbedded = "oe"

    fileprivate static func parse(_ component: Substring) -> Triple.Vendor? {
      switch component {
      case "apple":
        return .apple
      case "pc":
        return .pc
      case "scei":
        return .scei
      case "bgp":
        return .bgp
      case "bgq":
        return .bgq
      case "fsl":
        return .freescale
      case "ibm":
        return .ibm
      case "img":
        return .imaginationTechnologies
      case "mti":
        return .mipsTechnologies
      case "nvidia":
        return .nvidia
      case "csr":
        return .csr
      case "myriad":
        return .myriad
      case "amd":
        return .amd
      case "mesa":
        return .mesa
      case "suse":
        return .suse
      case "oe":
        return .openEmbedded
      default:
        return nil
      }
    }
  }
}

// MARK: - Parse OS

extension Triple {
  public enum OS: String, CaseIterable, TripleComponent, Sendable {
    case ananas
    case cloudABI = "cloudabi"
    case darwin
    case dragonFly = "dragonfly"
    case freebsd = "freebsd"
    case fuchsia
    case ios
    case kfreebsd
    case linux
    case lv2
    case macosx
    case netbsd
    case openbsd
    case solaris
    case win32
    case haiku
    case minix
    case rtems
    case nacl
    case cnk
    case aix
    case cuda
    case nvcl
    case amdhsa
    case ps4
    case elfiamcu
    case tvos
    case watchos
    case mesa3d
    case contiki
    case amdpal
    case hermitcore
    case hurd
    case wasi
    case emscripten
    case noneOS // 'OS' suffix purely to avoid name clash with Optional.none

    var name: String {
      return rawValue
    }

    fileprivate static func parse(_ os: Substring) -> Triple.OS? {
      switch os {
      case _ where os.hasPrefix("ananas"):
        return .ananas
      case _ where os.hasPrefix("cloudabi"):
        return .cloudABI
      case _ where os.hasPrefix("darwin"):
        return .darwin
      case _ where os.hasPrefix("dragonfly"):
        return .dragonFly
      case _ where os.hasPrefix("freebsd"):
        return .freebsd
      case _ where os.hasPrefix("fuchsia"):
        return .fuchsia
      case _ where os.hasPrefix("ios"):
        return .ios
      case _ where os.hasPrefix("kfreebsd"):
        return .kfreebsd
      case _ where os.hasPrefix("linux"):
        return .linux
      case _ where os.hasPrefix("lv2"):
        return .lv2
      case _ where os.hasPrefix("macos"):
        return .macosx
      case _ where os.hasPrefix("netbsd"):
        return .netbsd
      case _ where os.hasPrefix("openbsd"):
        return .openbsd
      case _ where os.hasPrefix("solaris"):
        return .solaris
      case _ where os.hasPrefix("win32"):
        return .win32
      case _ where os.hasPrefix("windows"):
        return .win32
      case _ where os.hasPrefix("haiku"):
        return .haiku
      case _ where os.hasPrefix("minix"):
        return .minix
      case _ where os.hasPrefix("rtems"):
        return .rtems
      case _ where os.hasPrefix("nacl"):
        return .nacl
      case _ where os.hasPrefix("cnk"):
        return .cnk
      case _ where os.hasPrefix("aix"):
        return .aix
      case _ where os.hasPrefix("cuda"):
        return .cuda
      case _ where os.hasPrefix("nvcl"):
        return .nvcl
      case _ where os.hasPrefix("amdhsa"):
        return .amdhsa
      case _ where os.hasPrefix("ps4"):
        return .ps4
      case _ where os.hasPrefix("elfiamcu"):
        return .elfiamcu
      case _ where os.hasPrefix("tvos"):
        return .tvos
      case _ where os.hasPrefix("watchos"):
        return .watchos
      case _ where os.hasPrefix("mesa3d"):
        return .mesa3d
      case _ where os.hasPrefix("contiki"):
        return .contiki
      case _ where os.hasPrefix("amdpal"):
        return .amdpal
      case _ where os.hasPrefix("hermit"):
        return .hermitcore
      case _ where os.hasPrefix("hurd"):
        return .hurd
      case _ where os.hasPrefix("wasi"):
        return .wasi
      case _ where os.hasPrefix("emscripten"):
        return .emscripten
      case _ where os.hasPrefix("none"):
        return .noneOS
      default:
        return nil
      }
    }

    fileprivate static func valueIsValid(_ value: Substring) -> Bool {
      parse(value) != nil || value.hasPrefix("cygwin") || value.hasPrefix("mingw")
    }
  }
}

// MARK: - Parse Environment

extension Triple {
  fileprivate enum EnvInfo: TripleComponent {
    case environmentOnly(Triple.Environment)
    case objectFormatOnly(Triple.ObjectFormat)
    case both(
      environment: Triple.Environment,
      objectFormat: Triple.ObjectFormat
    )

    var environment: Triple.Environment? {
      switch self {
      case .environmentOnly(let env), .both(let env, _):
        return env
      case .objectFormatOnly:
        return nil
      }
    }
    var objectFormat: Triple.ObjectFormat? {
      switch self {
      case .objectFormatOnly(let obj), .both(_, let obj):
        return obj
      case .environmentOnly:
        return nil
      }
    }

    fileprivate static func parse(_ component: Substring) -> EnvInfo? {
      switch (
        Triple.Environment.parse(component),
        Triple.ObjectFormat.parse(component)
      ) {
      case (nil, nil):
        return nil
      case (nil, let obj?):
        return .objectFormatOnly(obj)
      case (let env?, nil):
        return .environmentOnly(env)
      case (let env?, let obj?):
        return .both(environment: env, objectFormat: obj)
      }
    }
  }

  public enum Environment: String, CaseIterable, Equatable, Sendable {
    case eabihf
    case eabi
    case elfv1
    case elfv2
    case gnuabin32
    case gnuabi64
    case gnueabihf
    case gnueabi
    case gnux32
    case code16
    case gnu
    case android
    case musleabihf
    case musleabi
    case musl
    case msvc
    case itanium
    case cygnus
    case coreclr
    case simulator
    case macabi

    fileprivate static func parse(_ env: Substring) -> Triple.Environment? {
      switch env {
      case _ where env.hasPrefix("eabihf"):
        return .eabihf
      case _ where env.hasPrefix("eabi"):
        return .eabi
      case _ where env.hasPrefix("elfv1"):
        return .elfv1
      case _ where env.hasPrefix("elfv2"):
        return .elfv2
      case _ where env.hasPrefix("gnuabin32"):
        return .gnuabin32
      case _ where env.hasPrefix("gnuabi64"):
        return .gnuabi64
      case _ where env.hasPrefix("gnueabihf"):
        return .gnueabihf
      case _ where env.hasPrefix("gnueabi"):
        return .gnueabi
      case _ where env.hasPrefix("gnux32"):
        return .gnux32
      case _ where env.hasPrefix("code16"):
        return .code16
      case _ where env.hasPrefix("gnu"):
        return .gnu
      case _ where env.hasPrefix("android"):
        return .android
      case _ where env.hasPrefix("musleabihf"):
        return .musleabihf
      case _ where env.hasPrefix("musleabi"):
        return .musleabi
      case _ where env.hasPrefix("musl"):
        return .musl
      case _ where env.hasPrefix("msvc"):
        return .msvc
      case _ where env.hasPrefix("itanium"):
        return .itanium
      case _ where env.hasPrefix("cygnus"):
        return .cygnus
      case _ where env.hasPrefix("coreclr"):
        return .coreclr
      case _ where env.hasPrefix("simulator"):
        return .simulator
      case _ where env.hasPrefix("macabi"):
        return .macabi
      default:
        return nil
      }
    }

    fileprivate static func infer(archName: Substring?) -> Triple.Environment? {
      guard let firstComponent = archName else { return nil }

      switch firstComponent {
      case _ where firstComponent.hasPrefix("mipsn32"):
        return .gnuabin32
      case _ where firstComponent.hasPrefix("mips64"):
        return .gnuabi64
      case _ where firstComponent.hasPrefix("mipsisa64"):
        return .gnuabi64
      case _ where firstComponent.hasPrefix("mipsisa32"):
        return .gnu
      case "mips", "mipsel", "mipsr6", "mipsr6el":
        return .gnu
      default:
        return nil
      }
    }
  }
}

// MARK: - Parse Object Format

extension Triple {
  public enum ObjectFormat: Sendable {
    case coff
    case elf
    case macho
    case wasm
    case xcoff

    fileprivate static func parse(_ env: Substring) -> Triple.ObjectFormat? {
      switch env {
      // "xcoff" must come before "coff" because of the order-dependendent pattern matching.
      case _ where env.hasSuffix("xcoff"):
        return .xcoff
      case _ where env.hasSuffix("coff"):
        return .coff
      case _ where env.hasSuffix("elf"):
        return .elf
      case _ where env.hasSuffix("macho"):
        return .macho
      case _ where env.hasSuffix("wasm"):
        return .wasm
      default:
        return nil
      }
    }

    fileprivate static func infer(arch: Triple.Arch?, os: Triple.OS?) -> Triple.ObjectFormat {
      switch arch {
        case nil, .aarch64, .aarch64e, .aarch64_32, .arm, .thumb, .x86, .x86_64:
          if os?.isDarwin ?? false {
            return .macho
          } else if os?.isWindows ?? false {
            return .coff
          }
          return .elf

        case .aarch64_be: fallthrough
        case .arc: fallthrough
        case .amdgcn: fallthrough
        case .amdil: fallthrough
        case .amdil64: fallthrough
        case .armeb: fallthrough
        case .avr: fallthrough
        case .bpfeb: fallthrough
        case .bpfel: fallthrough
        case .hexagon: fallthrough
        case .lanai: fallthrough
        case .hsail: fallthrough
        case .hsail64: fallthrough
        case .kalimba: fallthrough
        case .le32: fallthrough
        case .le64: fallthrough
        case .mips: fallthrough
        case .mips64: fallthrough
        case .mips64el: fallthrough
        case .mipsel: fallthrough
        case .msp430: fallthrough
        case .nvptx: fallthrough
        case .nvptx64: fallthrough
        case .ppc64le: fallthrough
        case .r600: fallthrough
        case .renderscript32: fallthrough
        case .renderscript64: fallthrough
        case .riscv32: fallthrough
        case .riscv64: fallthrough
        case .shave: fallthrough
        case .sparc: fallthrough
        case .sparcel: fallthrough
        case .sparcv9: fallthrough
        case .spir: fallthrough
        case .spir64: fallthrough
        case .systemz: fallthrough
        case .tce: fallthrough
        case .tcele: fallthrough
        case .thumbeb: fallthrough
        case .xcore:
          return .elf

        case .ppc, .ppc64:
          if os?.isDarwin ?? false {
            return .macho
          } else if os == .aix {
            return .xcoff
          }
          return .elf

        case .wasm32, .wasm64:
          return .wasm
      }
    }

    var name: String {
      switch self {
        case .coff:   return "coff"
        case .elf:    return "elf"
        case .macho:  return "macho"
        case .wasm:   return "wasm"
        case .xcoff:  return "xcoff"
      }
    }
  }
}

// MARK: - OS tests

extension Triple.OS {

  public var isWindows: Bool {
    self == .win32
  }

  public var isAIX: Bool {
    self == .aix
  }

  /// isMacOSX - Is this a Mac OS X triple. For legacy reasons, we support both
  /// "darwin" and "osx" as OS X triples.
  public var isMacOSX: Bool {
    self == .darwin || self == .macosx
  }

  /// Is this an iOS triple.
  /// Note: This identifies tvOS as a variant of iOS. If that ever
  /// changes, i.e., if the two operating systems diverge or their version
  /// numbers get out of sync, that will need to be changed.
  /// watchOS has completely different version numbers so it is not included.
  public var isiOS: Bool {
    self == .ios || isTvOS
  }

  /// Is this an Apple tvOS triple.
  public var isTvOS: Bool {
    self == .tvos
  }

  /// Is this an Apple watchOS triple.
  public var isWatchOS: Bool {
    self == .watchos
  }

  /// isOSDarwin - Is this a "Darwin" OS (OS X, iOS, or watchOS).
  public var isDarwin: Bool {
    isMacOSX || isiOS || isWatchOS
  }
}

// MARK: - Versions

extension Triple {
  fileprivate func component(at i: Int) -> String {
    let components = triple.split(separator: "-", maxSplits: 3,
                                  omittingEmptySubsequences: false)
    guard i < components.endIndex else { return "" }
    return String(components[i])
  }

  public var archName: String { component(at: 0) }
  public var vendorName: String { component(at: 1) }

  /// Returns the name of the OS from the triple string.
  public var osName: String { component(at: 2) }

  public var environmentName: String { component(at: 3) }

  /// Parse the version number from the OS name component of the triple, if present.
  ///
  /// For example, "fooos1.2.3" would return (1, 2, 3). If an entry is not defined, it will
  /// be returned as 0.
  ///
  /// This does not do any normalization of the version; for instance, a
  /// `darwin` OS version number is not adjusted to match the equivalent
  /// `macosx` version number. It's usually better to use `version(for:)`
  /// to get Darwin versions.
  public var osVersion: Version {
    var osName = self.osName[...]

    // Assume that the OS portion of the triple starts with the canonical name.
    if let os = os {
      if osName.hasPrefix(os.name) {
        osName = osName.dropFirst(os.name.count)
      } else if os == .macosx, osName.hasPrefix("macos") {
        osName = osName.dropFirst(5)
      }
    }

    return Version(parse: osName)
  }

  public var osNameUnversioned: String {
    var canonicalOsName = self.osName[...]

    // Assume that the OS portion of the triple starts with the canonical name.
    if let os = os {
      if canonicalOsName.hasPrefix(os.name) {
        canonicalOsName = osName.prefix(os.name.count)
      } else if os == .macosx, osName.hasPrefix("macos") {
        canonicalOsName = osName.prefix(5)
      }
    }
    return String(canonicalOsName)
  }
}

// MARK: - Darwin Versions

extension Triple {
  /// Parse the version number as with getOSVersion and then
  /// translate generic "darwin" versions to the corresponding OS X versions.
  /// This may also be called with IOS triples but the OS X version number is
  /// just set to a constant 10.4.0 in that case.
  ///
  /// Returns true if successful.
  ///
  /// This accessor is semi-private; it's typically better to use `version(for:)` or
  /// `Triple.FeatureAvailability`.
  public var _macOSVersion: Version? {
    var version = osVersion

    switch os {
    case .darwin:
      // Default to darwin8, i.e., MacOSX 10.4.
      if version.major == 0 {
        version.major = 8
      }

      // Darwin version numbers are skewed from OS X versions.
      if version.major < 4 {
        return nil
      }

      if version.major <= 19 {
        version.micro = 0
        version.minor = version.major - 4
        version.major = 10
      } else {
        version.micro = 0
        version.minor = 0
        // darwin20+ corresponds to macOS 11+.
        version.major = version.major - 9
      }

    case .macosx:
      // Default to 10.4.
      if version.major == 0 {
        version.major = 10
        version.minor = 4
      }

      if version.major < 10 {
        return nil
      }

    case .ios, .tvos, .watchos:
       // Ignore the version from the triple.  This is only handled because the
       // the clang driver combines OS X and IOS support into a common Darwin
       // toolchain that wants to know the OS X version number even when targeting
       // IOS.
      version = Version(10, 4, 0)

    default:
      fatalError("unexpected OS for Darwin triple")
    }
    return version
  }

  /// Parse the version number as with getOSVersion.  This should
  /// only be called with IOS or generic triples.
  ///
  /// This accessor is semi-private; it's typically better to use `version(for:)` or
  /// `Triple.FeatureAvailability`.
  public var _iOSVersion: Version {
    switch os {
    case .darwin, .macosx:
      // Ignore the version from the triple.  This is only handled because the
      // the clang driver combines OS X and iOS support into a common Darwin
      // toolchain that wants to know the iOS version number even when targeting
      // OS X.
      return Version(5, 0, 0)
    case .ios, .tvos:
      var version = self.osVersion
      // Default to 5.0 (or 7.0 for arm64).
      if version.major == 0 {
        version.major = arch == .aarch64 ? 7 : 5
      }
      return version
    case .watchos:
      fatalError("conflicting triple info")
    default:
      fatalError("unexpected OS for Darwin triple")
    }
  }

  /// Parse the version number as with getOSVersion. This should only be
  /// called with WatchOS or generic triples.
  ///
  /// This accessor is semi-private; it's typically better to use `version(for:)` or
  /// `Triple.FeatureAvailability`.
  public var _watchOSVersion: Version {
    switch os {
    case .darwin, .macosx:
      // Ignore the version from the triple.  This is only handled because the
      // the clang driver combines OS X and iOS support into a common Darwin
      // toolchain that wants to know the iOS version number even when targeting
      // OS X.
      return Version(2, 0, 0)
    case .watchos:
      var version = self.osVersion
      if version.major == 0 {
        version.major = 2
      }
      return version
    case .ios:
      fatalError("conflicting triple info")
    default:
      fatalError("unexpected OS for Darwin triple")
    }
  }
}

// MARK: - Catalyst

extension Triple {
  @_spi(Testing) public var isMacCatalyst: Bool {
    return self.isiOS && !self.isTvOS && environment == .macabi
  }

  func isValidForZipperingWithTriple(_ variant: Triple) -> Bool {
    guard archName == variant.archName,
      arch == variant.arch,
      subArch == variant.subArch,
      vendor == variant.vendor else {
        return false
    }

    // Allow a macOS target and an iOS-macabi target variant
    // This is typically the case when zippering a library originally
    // developed for macOS.
    if self.isMacOSX && variant.isMacCatalyst {
      return true
    }

    // Allow an iOS-macabi target and a macOS target variant. This would
    // be the case when zippering a library originally developed for
    // iOS.
    if variant.isMacOSX && isMacCatalyst {
      return true
    }

    return false
  }
}

fileprivate extension Array {

  mutating func resize(toCount desiredCount: Int, paddingWith element: Element) {

    if desiredCount > count {
      append(contentsOf: repeatElement(element, count: desiredCount - count))
    } else if desiredCount < count {
      removeLast(count - desiredCount)
    }
  }
}
