//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// Computes CVSS v3.0/v3.1 base scores from vector strings.
public enum CVSSv3 {
    /// Returns the base score (0.0 to 10.0) for a vector such as
    /// `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H`, or nil if the vector is malformed.
    public static func baseScore(vector: String) -> Double? {
        let parts = vector.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let prefix = parts.first, prefix == "CVSS:3.0" || prefix == "CVSS:3.1" else { return nil }

        var metrics: [String: String] = [:]
        for part in parts.dropFirst() {
            let pair = part.split(separator: ":", omittingEmptySubsequences: false)
            guard pair.count == 2, metrics[String(pair[0])] == nil else { return nil }
            metrics[String(pair[0])] = String(pair[1])
        }

        guard
            let scopeChanged = ["U": false, "C": true][metrics["S"] ?? ""],
            let av = ["N": 0.85, "A": 0.62, "L": 0.55, "P": 0.2][metrics["AV"] ?? ""],
            let ac = ["L": 0.77, "H": 0.44][metrics["AC"] ?? ""],
            let pr = (scopeChanged
                ? ["N": 0.85, "L": 0.68, "H": 0.5]
                : ["N": 0.85, "L": 0.62, "H": 0.27])[metrics["PR"] ?? ""],
            let ui = ["N": 0.85, "R": 0.62][metrics["UI"] ?? ""],
            let c = Self.cia[metrics["C"] ?? ""],
            let i = Self.cia[metrics["I"] ?? ""],
            let a = Self.cia[metrics["A"] ?? ""]
        else { return nil }

        let iss = 1 - (1 - c) * (1 - i) * (1 - a)
        let impact = scopeChanged
            ? 7.52 * (iss - 0.029) - 3.25 * pow(iss - 0.02, 15)
            : 6.42 * iss
        guard impact > 0 else { return 0 }

        let exploitability = 8.22 * av * ac * pr * ui
        let raw = scopeChanged ? 1.08 * (impact + exploitability) : impact + exploitability
        return roundUp(min(raw, 10))
    }

    private static let cia = ["H": 0.56, "L": 0.22, "N": 0.0]

    /// The "Roundup" function from the CVSS v3.1 specification, which avoids
    /// floating point artifacts by working on integers.
    private static func roundUp(_ value: Double) -> Double {
        let scaled = Int((value * 100_000).rounded())
        if scaled % 10_000 == 0 {
            return Double(scaled) / 100_000
        }
        return (Double(scaled / 10_000) + 1) / 10
    }
}
