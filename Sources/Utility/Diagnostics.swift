/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

public struct AnyDiagnostic: DiagnosticData {
    public static let id = DiagnosticID(
        type: AnyDiagnostic.self,
        name: "org.swift.diags.anyerror",
        description: {
            $0 <<< { "\($0.anyError)" }
        }
    )

    public let anyError: Swift.Error

    public init(_ error: Swift.Error) {
        self.anyError = error
    }
}

/// Represents unknown diagnosic location.
public final class UnknownLocation: DiagnosticLocation {

    /// The singleton instance.
    public static let location = UnknownLocation()

    private init(){}

    public var localizedDescription: String {
        return "<unknown>"
    }
}

extension DiagnosticsEngine {
    public func emit(_ error: Swift.Error) {
        emit(data: AnyDiagnostic(error), location: UnknownLocation.location)
    }
}
