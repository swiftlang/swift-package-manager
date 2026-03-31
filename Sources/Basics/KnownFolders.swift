//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

#if os(Windows)
import WinSDK

private var KF_FLAG_DEFAULT: DWORD {
    DWORD(WinSDK.KF_FLAG_DEFAULT.rawValue)
}

private func SUCCEEDED(_ hr: HRESULT) -> Bool {
    hr >= 0
}

private func _url(for id: KNOWNFOLDERID) -> URL? {
    var pszPath: PWSTR?
    let hr: HRESULT = withUnsafePointer(to: id) { id in
        SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nil, &pszPath)
    }
    guard SUCCEEDED(hr) else { return nil }
    defer { CoTaskMemFree(pszPath) }
    return URL(filePath: String(decodingCString: pszPath!, as: UTF16.self), directoryHint: .isDirectory)
}
#endif

extension URL {
    /// Maps to the environment variable `%LOCALAPPDATA%\Programs`
    ///
    /// An example of a concrete path is `C:\Users\User\AppData\Local\Programs`
    public static var userProgramFiles: URL? {
#if os(Windows)
        _url(for: FOLDERID_UserProgramFiles)
#else
        nil
#endif
    }

    /// Maps to the environment variable `%ProgramFiles(x86)%`
    ///
    /// An example of a concrete path is `C:\Program Files (x86)`
    public static var programFilesX86: URL? {
#if os(Windows)
        _url(for: FOLDERID_ProgramFilesX86)
#else
        nil
#endif
    }

    /// The Windows system32 directory
    public static var system32: URL? {
#if os(Windows)
        _url(for: FOLDERID_System)
#else
        nil
#endif
    }
}
