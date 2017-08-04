/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility

/// A helper to substitute git URLs from a given set of regex rules.
///
/// This can be used to override the git URL of dependencies during the clone process.
struct GitURLSubstitutionHelper {

    /// A substitute rule.
    struct Rule: JSONMappable {

        /// The regex pattern of the rule.
        let regex: RegEx

        /// The template to use during substitution.
        let template: String

        init(json: JSON) throws {
            self.regex = try RegEx(pattern: json.get("pattern"))
            self.template = try json.get("template")
        }
    }

    /// The set of user provided rules.
    let rules: [Rule]

    public init(file: AbsolutePath) throws {
        let json = try JSON(bytes: localFileSystem.readFileContents(file))
        self.rules = try json.get("rules")
    }

    /// Substitute the given URL.
    func substitute(url: String) throws -> String {
        var url = url

        for rule in rules {
            // Run this rule on the URL.
            let numMatches = rule.regex.replaceMatches(in: &url, template: rule.template)

            // If there were matches, we are done.
            if numMatches > 0 {
                return url
            }
        }
        return url
    }
}
