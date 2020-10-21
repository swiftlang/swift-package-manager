/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

import Foundation
import TSCUtility

/// The diagnostic triggered when the package has a newer tools version than the installed tools.
public struct RequireNewerTools: DiagnosticData, Swift.Error {
    /// The path of the package.
    public let packagePath: String

    /// The version of the package.
    public let version: String?

    /// The installed tools version.
    public let installedToolsVersion: ToolsVersion

    /// The tools version of the package.
    public let packageToolsVersion: ToolsVersion

    public init(
        packagePath: String,
        version: String? = nil,
        installedToolsVersion: ToolsVersion,
        packageToolsVersion: ToolsVersion
    ) {
        self.packagePath = packagePath
        self.version = version
        self.installedToolsVersion = installedToolsVersion
        self.packageToolsVersion = packageToolsVersion
    }

    public var description: String {
        var text = "package at '\(packagePath)'"
        if let version = self.version {
            text += " @ \(version)"
        }
        text += " is using Swift tools version \(packageToolsVersion.description) but the installed version is \(installedToolsVersion.description)"
        return text
    }
}

/// The diagnostic triggered when the package has an unsupported tools version.
public struct UnsupportedToolsVersion: DiagnosticData, Swift.Error {
    /// The path of the package.
    public let packagePath: String

    /// The version of the package.
    public let version: String?

    /// The current tools version support by the tools.
    public let currentToolsVersion: ToolsVersion

    /// The tools version of the package.
    public let packageToolsVersion: ToolsVersion

    fileprivate var hintString: String {
        return "consider using '// swift-tools-version:\(currentToolsVersion.major).\(currentToolsVersion.minor)' to specify the current tools version"
    }

    public init(
        packagePath: String,
        version: String? = nil,
        currentToolsVersion: ToolsVersion,
        packageToolsVersion: ToolsVersion
    ) {
        self.packagePath = packagePath
        self.version = version
        self.currentToolsVersion = currentToolsVersion
        self.packageToolsVersion = packageToolsVersion
    }

    public var description: String {
        var text = "package at '\(self.packagePath)'"
        if let version = self.version {
            text += " @ \(version)"
        }
        text += " is using Swift tools version \(packageToolsVersion.description) which is no longer supported; \(hintString)"
        return text
    }
}
