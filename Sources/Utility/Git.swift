/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.ProcessInfo
import Basic

extension Version {
    static func vprefix(_ string: String) -> Version? {
        if string.first == "v" {
            return Version(string: String(string.dropFirst()))
        } else {
            return nil
        }
    }
}

public class Git {
    /// Compute the version -> tag mapping from a list of input `tags`.
    public static func convertTagsToVersionMap(_ tags: [String]) -> [Version: String] {
        // First, check if we need to restrict the tag set to version-specific tags.
        var knownVersions: [Version: String] = [:]
        for versionSpecificKey in Versioning.currentVersionSpecificKeys {
            for tag in tags where tag.hasSuffix(versionSpecificKey) {
                let specifier = String(tag.dropLast(versionSpecificKey.count))
                if let version = Version(string: specifier) ?? Version.vprefix(specifier) {
                    knownVersions[version] = tag
                }
            }

            // If we found tags at this version-specific key, we are done.
            if !knownVersions.isEmpty {
                return knownVersions
            }
        }

        // Otherwise, look for normal tags.
        for tag in tags {
            if let version = Version(string: tag) {
                knownVersions[version] = tag
            }
        }

        // If we didn't find any versions, look for 'v'-prefixed ones.
        //
        // FIXME: We should match both styles simultaneously.
        if knownVersions.isEmpty {
            for tag in tags {
                if let version = Version.vprefix(tag) {
                    knownVersions[version] = tag
                }
            }
        }
        return knownVersions
    }

    /// A shell command to run for Git. Can be either a name or a path.
    public static var tool: String = "git"

    /// Returns true if the git reference name is well formed.
    public static func checkRefFormat(ref: String) -> Bool {
        do {
            let result = try Process.popen(args: "git", "check-ref-format", "--allow-onelevel", ref)
            return result.exitStatus == .terminated(code: 0)
        } catch {
            return false
        }
    }

    /// Returns the environment variables for launching the git subprocess.
    ///
    /// This contains the current environment with custom overrides for using
    /// git from swift build.
    public static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Disable terminal prompts in git. This will make git error out and return
        // when it needs a user/pass etc instead of hanging the terminal (SR-3981).
        env["GIT_TERMINAL_PROMPT"] = "0"
        return env
    }
}
