//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//
// Warning: This file has been copied with minimal modifications from
// swift-driver to avoid a direct dependency. See Vendor/README.md for details.
//
// When updating, copy the file verbatim from swift-driver's
// Sources/SwiftDriver/Utilities/ directory and then re-apply the changes
// listed below. Changes marked [upstream] should be contributed back to
// swift-driver so that they can be dropped from this list.
//
// Changes:
// - Replaced usage of `\(_:or:)` string interpolation.
// - Removed `Triple.isDarwin` (it conflicts with SwiftPM's `Triple.isDarwin()`);
//   use `Triple.isDarwin(vendor:os:)` instead, which is internal rather than
//   fileprivate.
// - [upstream] Added DriverKit (`driverkit`) support.
// - [upstream] Accept `visionos` as an alias of `xros`, as LLVM does.
//
//===----------------------------------------------------------------------===//

/// Represents any of the "Apple" platforms handled by `DarwinToolchain`.
/// This boils down a lot of complicated logic about different variants and
/// environments into a straightforward, tightly-modeled type that can be
/// switched over.
///
/// `DarwinPlatform` does not contain version information, but
/// `Triple.version(for:)` retrieves a version based on the
/// corresponding `DarwinPlatform`.
public enum DarwinPlatform: Hashable {
  /// macOS, corresponding to the `macosx`, `macos`, and `darwin` OS names.
  case macOS

  /// iOS, corresponding to the `ios` and `iphoneos` OS names. This does not
  /// match tvOS.
  case iOS(Environment)

  /// tvOS, corresponding to the `tvos` OS name.
  case tvOS(EnvironmentWithoutCatalyst)

  /// watchOS, corresponding to the `watchos` OS name.
  case watchOS(EnvironmentWithoutCatalyst)

  /// visionOS, corresponding to the `xros` and `visionos` OS names.
  case visionOS(EnvironmentWithoutCatalyst)

  /// Firmware, corresponding to the `firmware` OS name.
  case Firmware

  /// DriverKit, corresponding to the `driverkit` OS name.
  case driverKit

  /// The most general form of environment information attached to a
  /// `DarwinPlatform`.
  ///
  /// The environment is a variant of the platform like `device` or `simulator`.
  /// Not all platforms support all values of environment. This type is a superset of
  /// all the environments available on any case.
  public enum Environment: Hashable {
    case device
    case simulator
    case catalyst

    var withoutCatalyst: EnvironmentWithoutCatalyst? {
      switch self {
      case .device:
        return .device
      case .simulator:
        return .simulator
      case .catalyst:
        return nil
      }
    }
  }

  public enum EnvironmentWithoutCatalyst: Hashable {
    case device
    case simulator
  }

  /// Returns the same platform, but with the environment replaced by
  /// `environment`. Returns `nil` if `environment` is not valid
  /// for `self`.
  func with(_ environment: Environment) -> DarwinPlatform? {
    switch self {
    case .macOS:
      guard environment == .device else { return nil }
      return .macOS
    case .iOS:
      return .iOS(environment)
    case .tvOS:
      guard let withoutCatalyst = environment.withoutCatalyst else { return nil }
      return .tvOS(withoutCatalyst)
    case .watchOS:
    guard let withoutCatalyst = environment.withoutCatalyst else { return nil }
      return .watchOS(withoutCatalyst)
    case .visionOS:
      guard let withoutCatalyst = environment.withoutCatalyst else { return nil }
      return .visionOS(withoutCatalyst)
    case .Firmware:
      guard environment == .device else { return nil }
      return .Firmware
    case .driverKit:
      guard environment == .device else { return nil }
      return .driverKit
    }
  }

  public var platformDisplayName: String {
    switch self {
    case .macOS:
      return "macOS"
    case .iOS(.device):
      return "iOS"
    case .iOS(.simulator):
      return "iOS Simulator"
    case .iOS(.catalyst):
      return "Mac Catalyst"
    case .tvOS(.device):
      return "tvOS"
    case .tvOS(.simulator):
      return "tvOS Simulator"
    case .watchOS(.device):
      return "watchOS"
    case .watchOS(.simulator):
      return "watchOS Simulator"
    case .visionOS(.device):
      return "visionOS"
    case .visionOS(.simulator):
      return "visionOS Simulator"
    case .Firmware:
      return "Firmware"
    case .driverKit:
      return "DriverKit"
    }
  }

  /// The platform name, i.e. the name clang uses to identify this platform in its
  /// resource directory.
  public var platformName: String {
    switch self {
    case .macOS:
      return "macosx"
    case .iOS(.device):
      return "iphoneos"
    case .iOS(.simulator):
      return "iphonesimulator"
    case .iOS(.catalyst):
      return "maccatalyst"
    case .tvOS(.device):
      return "appletvos"
    case .tvOS(.simulator):
      return "appletvsimulator"
    case .watchOS(.device):
      return "watchos"
    case .watchOS(.simulator):
      return "watchsimulator"
    case .visionOS(.device):
      return "xros"
    case .visionOS(.simulator):
      return "xrsimulator"
    case .driverKit:
      return "driverkit"
    default:
      fatalError("Unsupported Darwin platform \(self)")
    }
  }

  /// The name the linker uses to identify this platform.
  public var linkerPlatformName: String {
    switch self {
    case .macOS:
      return "macos"
    case .iOS(.device):
      return "ios"
    case .iOS(.simulator):
      return "ios-simulator"
    case .iOS(.catalyst):
      return "mac-catalyst"
    case .tvOS(.device):
      return "tvos"
    case .tvOS(.simulator):
      return "tvos-simulator"
    case .watchOS(.device):
      return "watchos"
    case .watchOS(.simulator):
      return "watchos-simulator"
    case .visionOS(.device):
      return "xros"
    case .visionOS(.simulator):
      return "xros-simulator"
    case .driverKit:
      return "driverkit"
    default:
      fatalError("Unsupported Darwin platform \(self)")
    }
  }


  /// The name used to identify this platform in compiler_rt file names.
  public var libraryNameSuffix: String {
    switch self {
    case .macOS:
      return "osx"
    case .iOS(.device):
      return "ios"
    case .iOS(.simulator):
      return "iossim"
    case .iOS(.catalyst):
      return "osx"
    case .tvOS(.device):
      return "tvos"
    case .tvOS(.simulator):
      return "tvossim"
    case .watchOS(.device):
      return "watchos"
    case .watchOS(.simulator):
      return "watchossim"
    case .visionOS(.device):
      return "xros"
    case .visionOS(.simulator):
      return "xrossim"
    case .driverKit:
      return "driverkit"
    default:
      fatalError("Unsupported Darwin platform \(self)")
    }
  }
}

extension Triple {
  /// If this is a Darwin device platform, should it be inferred to be a device simulator?
  public var _isSimulatorEnvironment: Bool {
    return environment == .simulator
  }

  /// Returns the OS version equivalent for the given platform, converting and
  /// defaulting various representations.
  ///
  /// - Parameter compatibilityPlatform: Overrides the platform to be fetched.
  ///   For compatibility reasons, you sometimes have to e.g. pass an argument with a macOS
  ///   version number even when you're building watchOS code. This parameter specifies the
  ///   platform you need a version number for; the method will then return an arbitrary but
  ///   suitable version number for `compatibilityPlatform`.
  ///
  /// - Precondition: `self` must be able to provide a version for `compatibilityPlatform`.
  ///   Not all combinations are valid; in particular, you cannot fetch a watchOS version
  ///   from an iOS/tvOS triple or vice versa.
  public func version(for compatibilityPlatform: DarwinPlatform? = nil)
    -> Triple.Version
  {
    switch compatibilityPlatform ?? darwinPlatform! {
    case .macOS:
      return _macOSVersion ?? osVersion
    case .iOS:
      return _iOSVersion
    case .tvOS:
      return _tvOSVersion
    case .watchOS:
      return _watchOSVersion
    case .visionOS:
      return _visionOSVersion
    case .Firmware:
      return _FirmwareVersion
    case .driverKit:
      return _driverKitVersion
    }
  }

  /// Returns the `DarwinPlatform` for this triple, or `nil` if it is a non-Darwin
  /// platform.
  ///
  /// - SeeAlso: DarwinPlatform
  public var darwinPlatform: DarwinPlatform? {
    func makeEnvironment() -> DarwinPlatform.EnvironmentWithoutCatalyst {
      _isSimulatorEnvironment ? .simulator : .device
    }
    switch os {
    case .darwin, .macosx:
      return .macOS
    case .ios:
      if isMacCatalyst {
        return .iOS(.catalyst)
      } else if _isSimulatorEnvironment {
        return .iOS(.simulator)
      } else {
        return .iOS(.device)
      }
    case .watchos:
      return .watchOS(makeEnvironment())
    case .tvos:
      return .tvOS(makeEnvironment())
    case .visionos:
      return .visionOS(makeEnvironment())
    case .firmware:
      return isAppleFirmware ? .Firmware : nil
    case .driverkit:
      return .driverKit
    default:
      return nil
    }
  }

  // The Darwin platform version used for linking.
  public var darwinLinkerPlatformVersion: Version {
    precondition(Triple.isDarwin(vendor: vendor, os: os))
    switch darwinPlatform! {
    case .macOS:
      // The integrated driver falls back to `osVersion` for invalid macOS
      // versions, this decision might be worth revisiting.
      let macVersion = _macOSVersion ?? osVersion
      // The first deployment of arm64 for macOS is version 11
      if macVersion.major < 11 && arch == .aarch64 {
        return Version(11, 0, 0)
      }

      return macVersion
    case .iOS(.catalyst):
      // Mac Catalyst on arm was introduced with an iOS deployment target of
      // 14.0; the linker doesn't want to see a deployment target before that.
      if _iOSVersion.major < 14 && arch == .aarch64 {
        return Version(14, 0, 0)
      }

      // Mac Catalyst was introduced with an iOS deployment target of 13.1;
      // the linker doesn't want to see a deployment target before that.
      if _iOSVersion.major < 13 {
        return Version(13, 1, 0)
      }

      return _iOSVersion
    case .iOS(_):
      // The first deployment of arm64 simulators is iOS 14.0;
      // the linker doesn't want to see a deployment target before that.
      if _isSimulatorEnvironment && _iOSVersion.major < 14 && arch == .aarch64 {
        return Version(14, 0, 0)
      }

      return _iOSVersion
    case .tvOS(_):
      // The first deployment of arm64 simulators is tvOS 14.0;
      // the linker doesn't want to see a deployment target before that.
      if _isSimulatorEnvironment && _tvOSVersion.major < 14 && arch == .aarch64 {
        return Version(14, 0, 0)
      }

      return _tvOSVersion
    case .watchOS(_):
      // The first deployment of arm64 simulators is watchOS 7;
      // the linker doesn't want to see a deployment target before that.
      if _isSimulatorEnvironment && osVersion.major < 7 && arch == .aarch64 {
        return Version(7, 0, 0)
      }

      return _watchOSVersion
    case .visionOS(_):
      return _visionOSVersion
    case .Firmware:
      return _FirmwareVersion
    case .driverKit:
      return _driverKitVersion
    }
  }


  /// The "os" component of the Clang compiler resource library directory (`<ResourceDir>/lib/<OSName>`).
  /// Must be kept in sync with Clang driver:
  /// https://github.com/llvm/llvm-project/blob/llvmorg-20.1.4/clang/lib/Driver/ToolChain.cpp#L690
  @_spi(Testing) public var clangOSLibName: String {
    guard let os else {
      return osName
    }
    if Triple.isDarwin(vendor: vendor, os: os) {
      return "darwin"
    }

    switch os {
    case .freeBSD: return "freebsd"
    case .netbsd: return "netbsd"
    case .openbsd: return "openbsd"
    case .aix: return "aix"
    default: return osName
    }
  }

  /// The platform name, i.e. the name Swift uses to identify this target in its
  /// resource directory.
  ///
  /// - Parameter conflatingDarwin: If true, all Darwin platforms will be
  ///   identified as just `darwin` instead of by individual platform names.
  ///   Defaults to `false`.
  public func platformName(conflatingDarwin: Bool = false) -> String? {
    switch os {
    case nil:
      fatalError("unknown OS")
    case .darwin, .macosx, .ios, .tvos, .watchos, .visionos, .firmware, .driverkit:
      guard let darwinPlatform = darwinPlatform else {
        fatalError("unsupported darwin platform kind?")
      }
      return conflatingDarwin ? "darwin" : darwinPlatform.platformName

    case .linux:
      switch environment {
      case .musl where vendor == .swift:
        // The triple for linux-static is <arch>-swift-linux-musl, to distinguish
        // it from a "normal" musl set-up (ala Alpine).
        return "linux-static"
      case .musl, .musleabihf, .musleabi:
        return "musl"
      case .android:
        return "android"
      default:
        return "linux"
      }
    case .freeBSD:
      return "freebsd"
    case .openbsd:
      return "openbsd"
    case .win32:
      switch environment {
      case .cygnus:
        return "cygwin"
      case .gnu:
        return "mingw"
      case .msvc, .itanium:
        return "windows"
      default:
        if let environment = environment {
          fatalError("unsupported Windows environment: \(environment)")
        } else {
          fatalError("unsupported Windows environment: nil")
        }
      }
    case .ps4:
      return "ps4"
    case .haiku:
      return "haiku"
    case .wasi:
      return "wasi"
    case .emscripten:
      return "emscripten"
    case .noneOS:
      return nil

    // Explicitly spell out the remaining cases to force a compile error when
    // Triple updates
    case .ananas, .cloudABI, .dragonFly, .fuchsia, .kfreebsd, .lv2, .netbsd,
         .solaris, .minix, .rtems, .nacl, .cnk, .aix, .cuda, .nvcl, .amdhsa,
         .elfiamcu, .mesa3d, .contiki, .amdpal, .hermitcore, .hurd:
      return nil
    }
  }
}

extension Triple {
  /// Represents the availability of a feature that is supported on some platforms
  /// and versions, but not all. For Darwin versions, the version numbers provided
  /// should be the version where the feature was added or the change was
  /// introduced, because all version checks are in the form of
  /// `tripleVersion >= featureVersion`.
  ///
  /// - SeeAlso: `Triple.supports(_:)`
  public struct FeatureAvailability: Sendable {

    public enum Availability: Sendable {
      case unavailable
      case available(since: Version)
      case availableInAllVersions
    }

    public let macOS: Availability
    public let iOS: Availability
    public let tvOS: Availability
    public let watchOS: Availability
    public var visionOS: Availability

    // TODO: We should have linux, windows, etc.
    public let nonDarwin: Bool

    /// Describes the availability of a feature that is supported on multiple platforms,
    /// but is tied to a particular version.
    public init(
      macOS: Availability,
      iOS: Availability,
      tvOS: Availability,
      watchOS: Availability,
      nonDarwin: Bool = false
    ) {
      self.macOS = macOS
      self.iOS = iOS
      self.tvOS = tvOS
      self.watchOS = watchOS
      self.nonDarwin = nonDarwin
      self.visionOS = iOS
    }

    public func withVisionOS(_ visionOS: Availability) -> FeatureAvailability {
      var res = self
      res.visionOS = visionOS
      return res
    }
    /// Returns the version when the feature was introduced on the specified Darwin
    /// platform, or `.unavailable` if the feature has not been introduced there.
    public subscript(darwinPlatform: DarwinPlatform) -> Availability {
      switch darwinPlatform {
      case .macOS:
        return macOS
      case .iOS:
        return iOS
      case .tvOS:
        return tvOS
      case .watchOS:
        return watchOS
      case .visionOS:
        return visionOS
      case .Firmware, .driverKit:
        return .availableInAllVersions
      }
    }
  }

  /// Checks whether the triple supports the specified feature, i.e., the feature
  /// has been introduced by the OS and version indicated by the triple.
  public func supports(_ feature: FeatureAvailability) -> Bool {
    guard let darwinPlatform = darwinPlatform else {
      return feature.nonDarwin
    }

    switch feature[darwinPlatform] {
    case .unavailable:
      return false
    case .available(let introducedVersion):
      return version(for: darwinPlatform) >= introducedVersion
    case .availableInAllVersions:
      return true
    }
  }
}

extension Triple.FeatureAvailability {
  /// Linking `libarclite` is unnecessary for triples supporting this feature.
  ///
  /// This impacts the `-link-objc-runtime` flag in Swift, which is akin to the
  /// `-fobjc-link-runtime` build setting in clang. When set, these flags
  /// automatically link libobjc, and any compatibility libraries that don't
  /// ship with the OS. The versions here are the first OSes that support
  /// ARC natively in their respective copies of the Objective-C runtime,
  /// and therefore do not require additional support libraries.
  static let nativeARC = Self(
    macOS: .available(since: Triple.Version(10, 11, 0)),
    iOS: .available(since: Triple.Version(9, 0, 0)),
    tvOS: .available(since: Triple.Version(9, 0, 0)),
    watchOS: .availableInAllVersions
  )
  // When updating the versions listed here, please record the most recent
  // feature being depended on and when it was introduced:
  //
  // - Make assigning 'nil' to an NSMutableDictionary subscript delete the
  //   entry, like it does for Swift.Dictionary, rather than trap.
}
