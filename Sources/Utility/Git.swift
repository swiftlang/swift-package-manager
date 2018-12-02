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
    /// Try a version from a git tag
    ///
    /// - Parameter tag: A version string possibly prepended with "v"
    init?(tag: String) {
        if tag.first == "v" {
            self.init(string: String(tag.dropFirst()))
        } else {
            self.init(string: tag)
        }
    }
}

public class Git {
    /// Compute the version -> tags mapping from a list of input `tags`.
    public static func convertTagsToVersionMap(_ tags: [String]) -> [Version: [String]] {
        // First, check if we need to restrict the tag set to version-specific tags.
        var knownVersions: [Version: [String]] = [:]
        var versionSpecificKnownVersions: [Version: [String]] = [:]

        for tag in tags {
            for versionSpecificKey in Versioning.currentVersionSpecificKeys {
                if tag.hasSuffix(versionSpecificKey) {
                    let trimmedTag = String(tag.dropLast(versionSpecificKey.count))
                    if let version = Version(tag: trimmedTag) {
                        versionSpecificKnownVersions[version, default: []].append(tag)
                    }
                    break
                }
            }
            
            if let version = Version(tag: tag) {
                knownVersions[version, default: []].append(tag)
            }
        }
        // Check if any version specific tags were found.
        // If true, then return the version specific tags,
        // or else return the version independent tags.
        if !versionSpecificKnownVersions.isEmpty {
            return versionSpecificKnownVersions
        } else {
            return knownVersions
        }
    }

    /// A shell command to run for Git. Can be either a name or a path.
    public static var tool: String = "git"

    /// Returns true if the git reference name is well formed.
    public static func checkRefFormat(ref: String) -> Bool {
        do {
            let result = try Process.popen(args: tool, "check-ref-format", "--allow-onelevel", ref)
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

        // These variables are inserted into the environment when shelling out
        // to git if not already present.
        let underrideVariables =  [
            // Disable terminal prompts in git. This will make git error out and return
            // when it needs a user/pass etc instead of hanging the terminal (SR-3981).
            "GIT_TERMINAL_PROMPT": "0",

            // The above is env variable is not enough. However, ssh_config's batch
            // mode is made for this purpose. see: https://linux.die.net/man/5/ssh_config
            "GIT_SSH_COMMAND": "ssh -oBatchMode=yes",
        ]

        for (key, value) in underrideVariables {
            // Skip this key is already present in the env.
            if env.keys.contains(key) { continue }

            env[key] = value
        }

        return env
    }
}
