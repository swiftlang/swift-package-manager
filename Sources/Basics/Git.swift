/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.ProcessInfo
import TSCBasic

@_spi(SwiftPMInternal)
public enum Git {
    /// A shell command to run for Git. Can be either a name or a path.
    ///  - Note: modification is not thread safe, designed for testing only
    @_spi(SwiftPMInternal)
    public static var tool: String = "git\(executableFileSuffix)"

    /// Returns true if the git reference name is well formed.
    @_spi(SwiftPMInternal)
    public static func checkRefFormat(ref: String) -> Bool {
        do {
            let result = try Process.popen(args: tool, "check-ref-format", "--allow-onelevel", ref)
            return result.exitStatus == .terminated(code: 0)
        } catch {
            return false
        }
    }

    private static var _gitEnvironment = ProcessEnv.block

    /// Returns the environment variables for launching the git subprocess.
    ///
    /// This contains the current environment with custom overrides for using
    /// git from swift build.
    ///  - Note: modification is not thread safe, designed for testing only
    @_spi(SwiftPMInternal)
    public static var environmentBlock: ProcessEnvironmentBlock {
        get {
            var env = Self._gitEnvironment

            // These variables are inserted into the environment when shelling out
            // to git if not already present.
            let underrideVariables: ProcessEnvironmentBlock =  [
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
        set {
            Self._gitEnvironment = newValue
        }
    }
}
