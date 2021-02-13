/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch
import struct Foundation.Data
import struct Foundation.Date
import class Foundation.FileManager
import struct Foundation.URL

import TSCBasic

#if canImport(Security)
import Security
#endif

protocol CertificatePolicy {
    /// Validates the given certificate chain.
    ///
    /// - Parameters:
    ///   - certChainPaths: Paths to each certificate in the chain. The certificate being verified must be the first element of the array,
    ///                     with its issuer the next element and so on, and the root CA certificate is last.
    ///   - callback: The callback to invoke when the result is available.
    func validate(certChain: [Certificate], callback: @escaping (Result<Void, Error>) -> Void)
}

extension CertificatePolicy {
    /// Verifies the certificate.
    ///
    /// - Parameters:
    ///   - certChain: The entire certificate chain. The certificate being verified must be the first element of the array.
    ///   - anchorCerts: On Apple platforms, these are root certificates to trust **in addition** to the operating system's trust store.
    ///                  On other platforms, these are the **only** root certificates to be trusted.
    ///   - verifyDate: Overrides the timestamp used for checking certificate expiry (e.g., for testing). By default the current time is used.
    ///   - diagnosticsEngine: The `DiagnosticsEngine` for emitting warnings and errors
    ///   - callbackQueue: The `DispatchQueue` to use for callbacks
    ///   - callback: The callback to invoke when the result is available.
    func verify(certChain: [Certificate],
                anchorCerts: [Certificate]?,
                verifyDate: Date? = nil,
                diagnosticsEngine: DiagnosticsEngine,
                callbackQueue: DispatchQueue,
                callback: @escaping (Result<Void, Error>) -> Void) {
        let wrappedCallback: (Result<Void, Error>) -> Void = { result in callbackQueue.async { callback(result) } }

        guard !certChain.isEmpty else {
            return wrappedCallback(.failure(CertificatePolicyError.emptyCertChain))
        }

        #if canImport(Security)
        let policy = SecPolicyCreateBasicX509()
        let revocationPolicy = SecPolicyCreateRevocation(kSecRevocationOCSPMethod)

        var secTrust: SecTrust?
        guard SecTrustCreateWithCertificates(certChain.map { $0.underlying } as CFArray,
                                             [policy, revocationPolicy] as CFArray,
                                             &secTrust) == errSecSuccess,
            let trust = secTrust else {
            return wrappedCallback(.failure(CertificatePolicyError.trustSetupFailure))
        }

        if let anchorCerts = anchorCerts {
            SecTrustSetAnchorCertificates(trust, anchorCerts.map { $0.underlying } as CFArray)
        }
        if let verifyDate = verifyDate {
            SecTrustSetVerifyDate(trust, verifyDate as CFDate)
        }

        callbackQueue.async {
            // This automatically searches the user's keychain and system's store for any needed
            // certificates. Passing the entire cert chain is optional and is an optimization.
            SecTrustEvaluateAsyncWithError(trust, callbackQueue) { _, isTrusted, _ in
                guard isTrusted else {
                    return wrappedCallback(.failure(CertificatePolicyError.invalidCertChain))
                }
                wrappedCallback(.success(()))
            }
        }
        #else
        fatalError("Not implemented: \(#function)")
        #endif
    }
}

// MARK: - Supporting methods and types

extension CertificatePolicy {
    func hasExtension(oid: String, in certificate: Certificate) throws -> Bool {
        #if canImport(Security)
        guard let dict = SecCertificateCopyValues(certificate.underlying, [oid as CFString] as CFArray, nil) as? [CFString: Any] else {
            throw CertificatePolicyError.extensionFailure
        }
        return !dict.isEmpty
        #else
        fatalError("Not implemented: \(#function)")
        #endif
    }

    func hasExtendedKeyUsage(_ usage: CertificateExtendedKeyUsage, in certificate: Certificate) throws -> Bool {
        #if canImport(Security)
        guard let dict = SecCertificateCopyValues(certificate.underlying, [kSecOIDExtendedKeyUsage] as CFArray, nil) as? [CFString: Any] else {
            throw CertificatePolicyError.extensionFailure
        }
        guard let usageDict = dict[kSecOIDExtendedKeyUsage] as? [CFString: Any],
            let usages = usageDict[kSecPropertyKeyValue] as? [Data] else {
            return false
        }
        return usages.first(where: { $0 == usage.data }) != nil
        #else
        fatalError("Not implemented: \(#function)")
        #endif
    }

    /// Checks that the certificate supports OCSP. This **must** be done before calling `verify` to ensure
    /// the necessary properties are in place to trigger revocation check.
    func supportsOCSP(certificate: Certificate) throws -> Bool {
        #if canImport(Security)
        // Check that certificate has "Certificate Authority Information Access" extension and includes OCSP as access method.
        // The actual revocation check will be done by the Security framework in `verify`.
        guard let dict = SecCertificateCopyValues(certificate.underlying, [kSecOIDAuthorityInfoAccess] as CFArray, nil) as? [CFString: Any] else { // ignore error
            throw CertificatePolicyError.extensionFailure
        }
        guard let infoAccessDict = dict[kSecOIDAuthorityInfoAccess] as? [CFString: Any],
            let infoAccessValue = infoAccessDict[kSecPropertyKeyValue] as? [[CFString: Any]] else {
            return false
        }
        return infoAccessValue.first(where: { valueDict in valueDict[kSecPropertyKeyValue] as? String == "1.3.6.1.5.5.7.48.1" }) != nil
        #else
        fatalError("Not implemented: \(#function)")
        #endif
    }
}

enum CertificateExtendedKeyUsage {
    case codeSigning

    #if canImport(Security)
    var data: Data {
        switch self {
        case .codeSigning:
            // https://stackoverflow.com/questions/49489591/how-to-extract-or-compare-ksecpropertykeyvalue-from-seccertificate
            // https://github.com/google/der-ascii/blob/cd91cb85bb0d71e4611856e4f76f5110609d7e42/cmd/der2ascii/oid_names.go#L100
            return Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x03])
        }
    }
    #endif
}

extension CertificatePolicy {
    static func loadCerts(at directory: URL, diagnosticsEngine: DiagnosticsEngine) -> [Certificate] {
        var certs = [Certificate]()
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                do {
                    certs.append(try Certificate(derEncoded: Data(contentsOf: fileURL)))
                } catch {
                    diagnosticsEngine.emit(warning: "The certificate \(fileURL) is invalid: \(error)")
                }
            }
        }
        return certs
    }
}

enum CertificatePolicyError: Error, Equatable {
    case emptyCertChain
    case trustSetupFailure
    case invalidCertChain
    case subjectUserIDMismatch
    case codeSigningCertRequired
    case ocspSupportRequired
    case unexpectedCertChainLength
    case missingRequiredExtension
    case extensionFailure
//    case ocspFailure
}

// MARK: - Certificate policies

/// Default policy for validating certificates used to sign package collections.
///
/// Certificates must satisfy these conditions:
///   - The timestamp at which signing/verification is done must fall within the signing certificate’s validity period.
///   - The certificate’s “Extended Key Usage” extension must include “Code Signing”.
///   - The certificate must use either 256-bit EC (recommended) or 2048-bit RSA key.
///   - The certificate must not be revoked. The certificate authority must support OCSP, which means the certificate must have the
///   "Certificate Authority Information Access" extension that includes OCSP as a method, specifying the responder’s URL.
///   - The certificate chain is valid and root certificate must be trusted.
struct DefaultCertificatePolicy: CertificatePolicy {
    let trustedRoots: [Certificate]?
    let expectedSubjectUserID: String?

    private let callbackQueue: DispatchQueue
    private let diagnosticsEngine: DiagnosticsEngine

    /// Initializes a `DefaultCertificatePolicy`.
    /// - Parameters:
    ///   - trustedRootCertsDir: On Apple platforms, all root certificates that come preinstalled with the OS are automatically trusted.
    ///                          Users may specify additional certificates to trust by placing them in `trustedRootCertsDir` and
    ///                          configure the signing tool or SwiftPM to use it. On non-Apple platforms, only trust root certificates in
    ///                          `trustedRootCertsDir` are trusted.
    ///   - expectedSubjectUserID: The subject user ID that must match if specified.
    ///   - callbackQueue: The `DispatchQueue` to use for callbacks
    ///   - diagnosticsEngine: The `DiagnosticsEngine` for emitting warnings and errors.
    init(trustedRootCertsDir: URL? = nil, expectedSubjectUserID: String? = nil, callbackQueue: DispatchQueue, diagnosticsEngine: DiagnosticsEngine) {
        self.trustedRoots = trustedRootCertsDir.map { Self.loadCerts(at: $0, diagnosticsEngine: diagnosticsEngine) }
        self.expectedSubjectUserID = expectedSubjectUserID
        self.callbackQueue = callbackQueue
        self.diagnosticsEngine = diagnosticsEngine
    }

    func validate(certChain: [Certificate], callback: @escaping (Result<Void, Error>) -> Void) {
        let wrappedCallback: (Result<Void, Error>) -> Void = { result in self.callbackQueue.async { callback(result) } }

        guard !certChain.isEmpty else {
            return wrappedCallback(.failure(CertificatePolicyError.emptyCertChain))
        }

        do {
            // Check if subject user ID matches
            if let expectedSubjectUserID = self.expectedSubjectUserID {
                guard try certChain[0].subject().userID == expectedSubjectUserID else {
                    return wrappedCallback(.failure(CertificatePolicyError.subjectUserIDMismatch))
                }
            }

            // Must be a code signing certificate
            guard try self.hasExtendedKeyUsage(.codeSigning, in: certChain[0]) else {
                return wrappedCallback(.failure(CertificatePolicyError.codeSigningCertRequired))
            }
            // Must support OCSP
            guard try self.supportsOCSP(certificate: certChain[0]) else {
                return wrappedCallback(.failure(CertificatePolicyError.ocspSupportRequired))
            }

            // Verify the cert chain - if it is trusted then cert chain is valid
            self.verify(certChain: certChain, anchorCerts: self.trustedRoots, diagnosticsEngine: self.diagnosticsEngine, callbackQueue: self.callbackQueue, callback: callback)
        } catch {
            return wrappedCallback(.failure(error))
        }
    }
}

/// Policy for validating developer.apple.com certificates.
///
/// This has the same requirements as `DefaultCertificatePolicy` plus additional
/// marker extensions for Apple Distribution certifiications.
struct AppleDeveloperCertificatePolicy: CertificatePolicy {
    private static let expectedCertChainLength = 3
    private static let appleDistributionIOSMarker = "1.2.840.113635.100.6.1.4"
    private static let appleDistributionMacOSMarker = "1.2.840.113635.100.6.1.7"
    private static let appleIntermediateMarker = "1.2.840.113635.100.6.2.1"

    let trustedRoots: [Certificate]?
    let expectedSubjectUserID: String?

    private let callbackQueue: DispatchQueue
    private let diagnosticsEngine: DiagnosticsEngine

    /// Initializes a `AppleDeveloperCertificatePolicy`.
    /// - Parameters:
    ///   - trustedRootCertsDir: On Apple platforms, all root certificates that come preinstalled with the OS are automatically trusted.
    ///                          Users may specify additional certificates to trust by placing them in `trustedRootCertsDir` and
    ///                          configure the signing tool or SwiftPM to use it. On non-Apple platforms, only trust root certificates in
    ///                          `trustedRootCertsDir` are trusted.
    ///   - expectedSubjectUserID: The subject user ID that must match if specified.
    ///   - callbackQueue: The `DispatchQueue` to use for callbacks
    ///   - diagnosticsEngine: The `DiagnosticsEngine` for emitting warnings and errors.
    init(trustedRootCertsDir: URL? = nil, expectedSubjectUserID: String? = nil, callbackQueue: DispatchQueue, diagnosticsEngine: DiagnosticsEngine) {
        self.trustedRoots = trustedRootCertsDir.map { Self.loadCerts(at: $0, diagnosticsEngine: diagnosticsEngine) }
        self.expectedSubjectUserID = expectedSubjectUserID
        self.callbackQueue = callbackQueue
        self.diagnosticsEngine = diagnosticsEngine
    }

    func validate(certChain: [Certificate], callback: @escaping (Result<Void, Error>) -> Void) {
        let wrappedCallback: (Result<Void, Error>) -> Void = { result in self.callbackQueue.async { callback(result) } }

        guard !certChain.isEmpty else {
            return wrappedCallback(.failure(CertificatePolicyError.emptyCertChain))
        }
        // developer.apple.com cert chain is always 3-long
        guard certChain.count == Self.expectedCertChainLength else {
            return wrappedCallback(.failure(CertificatePolicyError.unexpectedCertChainLength))
        }

        do {
            // Check if subject user ID matches
            if let expectedSubjectUserID = self.expectedSubjectUserID {
                guard try certChain[0].subject().userID == expectedSubjectUserID else {
                    return wrappedCallback(.failure(CertificatePolicyError.subjectUserIDMismatch))
                }
            }

            // Check marker extensions (certificates issued post WWDC 2019 have both extensions but earlier ones have just one depending on platform)
            guard try (self.hasExtension(oid: Self.appleDistributionIOSMarker, in: certChain[0]) || self.hasExtension(oid: Self.appleDistributionMacOSMarker, in: certChain[0])) else {
                return wrappedCallback(.failure(CertificatePolicyError.missingRequiredExtension))
            }
            guard try self.hasExtension(oid: Self.appleIntermediateMarker, in: certChain[1]) else {
                return wrappedCallback(.failure(CertificatePolicyError.missingRequiredExtension))
            }

            // Must be a code signing certificate
            guard try self.hasExtendedKeyUsage(.codeSigning, in: certChain[0]) else {
                return wrappedCallback(.failure(CertificatePolicyError.codeSigningCertRequired))
            }
            // Must support OCSP
            guard try self.supportsOCSP(certificate: certChain[0]) else {
                return wrappedCallback(.failure(CertificatePolicyError.ocspSupportRequired))
            }

            // Verify the cert chain - if it is trusted then cert chain is valid
            self.verify(certChain: certChain, anchorCerts: self.trustedRoots, diagnosticsEngine: self.diagnosticsEngine, callbackQueue: self.callbackQueue, callback: callback)
        } catch {
            return wrappedCallback(.failure(error))
        }
    }
}

public enum CertificatePolicyKey: Equatable, Hashable {
    case `default`(subjectUserID: String?)
    case appleDistribution(subjectUserID: String?)

    /// For internal-use only
    case custom

    public static let `default` = CertificatePolicyKey.default(subjectUserID: nil)
    public static let appleDistribution = CertificatePolicyKey.appleDistribution(subjectUserID: nil)
}
