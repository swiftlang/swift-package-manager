//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import struct Foundation.Data
import struct Foundation.Date
import class Foundation.FileManager
import struct Foundation.URL

import Basics
import TSCBasic

#if os(macOS)
import Security
#elseif os(Linux) || os(Windows) || os(Android)
@_implementationOnly import CCryptoBoringSSL
@_implementationOnly import PackageCollectionsSigningLibc
#endif

let appleDistributionIOSMarker = "1.2.840.113635.100.6.1.4"
let appleDistributionMacOSMarker = "1.2.840.113635.100.6.1.7"
let appleSwiftPackageCollectionMarker = "1.2.840.113635.100.6.1.35"
let appleIntermediateMarkers = ["1.2.840.113635.100.6.2.1", "1.2.840.113635.100.6.2.15"]

// For BoringSSL only - the Security framework recognizes these marker extensions
#if os(Linux) || os(Windows) || os(Android)
let supportedCriticalExtensions: Set<String> = [appleSwiftPackageCollectionMarker, // This isn't a critical extension but including it just in case,
                                                appleDistributionIOSMarker, appleDistributionMacOSMarker,
                                                // Support "Apple Development" cert markers--they are valid code signing certs after all and satisfy DefaultCertificatePolicy
                                                "1.2.840.113635.100.6.1.2", "1.2.840.113635.100.6.1.12"]
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
    #if os(macOS)
    /// Verifies a certificate chain.
    ///
    /// - Parameters:
    ///   - certChain: The entire certificate chain. The certificate being verified must be the first element of the array.
    ///   - anchorCerts: On Apple platforms, these are root certificates to trust **in addition** to the operating system's trust store.
    ///                  On other platforms, these are the **only** root certificates to be trusted.
    ///   - verifyDate: Overrides the timestamp used for checking certificate expiry (e.g., for testing). By default the current time is used.
    ///   - callbackQueue: The `DispatchQueue` to use for callbacks
    ///   - callback: The callback to invoke when the result is available.
    func verify(certChain: [Certificate],
                anchorCerts: [Certificate]?,
                verifyDate: Date? = nil,
                callbackQueue: DispatchQueue,
                callback: @escaping (Result<Void, Error>) -> Void) {
        let wrappedCallback: (Result<Void, Error>) -> Void = { result in callbackQueue.async { callback(result) } }

        guard !certChain.isEmpty else {
            return wrappedCallback(.failure(CertificatePolicyError.emptyCertChain))
        }

        let policy = SecPolicyCreateBasicX509()
        let revocationPolicy = SecPolicyCreateRevocation(kSecRevocationOCSPMethod)

        var secTrust: SecTrust?
        guard SecTrustCreateWithCertificates(certChain.map({ $0.underlying }) as CFArray,
                                             [policy, revocationPolicy] as CFArray,
                                             &secTrust) == errSecSuccess,
            let trust = secTrust else {
            return wrappedCallback(.failure(CertificatePolicyError.trustSetupFailure))
        }

        if let anchorCerts {
            SecTrustSetAnchorCertificates(trust, anchorCerts.map { $0.underlying } as CFArray)
        }
        if let verifyDate {
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
    }

    #elseif os(Linux) || os(Windows) || os(Android)
    typealias BoringSSLVerifyCallback = @convention(c) (CInt, OpaquePointer?) -> CInt

    /// Verifies a certificate chain.
    ///
    /// - Parameters:
    ///   - certChain: The entire certificate chain. The certificate being verified must be the first element of the array.
    ///   - anchorCerts: On Apple platforms, these are root certificates to trust **in addition** to the operating system's trust store.
    ///                  On other platforms, these are the **only** root certificates to be trusted.
    ///   - verifyDate: Overrides the timestamp used for checking certificate expiry (e.g., for testing). By default the current time is used.
    ///   - httpClient: HTTP client for OCSP requests
    ///   - observabilityScope: observabilityScope to emit diagnostics on
    ///   - callbackQueue: The `DispatchQueue` to use for callbacks
    ///   - callback: The callback to invoke when the result is available.
    func verify(certChain: [Certificate],
                anchorCerts: [Certificate]? = nil,
                verifyDate: Date? = nil,
                httpClient: LegacyHTTPClient?,
                observabilityScope: ObservabilityScope,
                callbackQueue: DispatchQueue,
                callback: @escaping (Result<Void, Error>) -> Void) {
        let wrappedCallback: (Result<Void, Error>) -> Void = { result in callbackQueue.async { callback(result) } }

        guard !certChain.isEmpty else {
            return wrappedCallback(.failure(CertificatePolicyError.emptyCertChain))
        }

        // On non-Apple platforms we don't trust any of the system root certs, so if `anchorCerts`,
        // which is a combination of user-configured and SwiftPM-provided roots, is empty the trust
        // evaluation of `certChain` will always fail.
        guard let anchorCerts = anchorCerts, !anchorCerts.isEmpty else {
            return wrappedCallback(.failure(CertificatePolicyError.noTrustedRootCertsConfigured))
        }

        // Make sure certChain and underlying pointers stay in scope for sk_X509 until we are done verifying
        let error: Error? = withExtendedLifetime(certChain) {
            // Cert chain
            let x509Stack = CCryptoBoringSSL_sk_X509_new_null()
            defer { CCryptoBoringSSL_sk_X509_free(x509Stack) }

            for i in 1 ..< certChain.count {
                guard certChain[i].withUnsafeMutablePointer({ CCryptoBoringSSL_sk_X509_push(x509Stack, $0) }) > 0 else {
                    return CertificatePolicyError.trustSetupFailure
                }
            }

            // Trusted certs
            let x509Store = CCryptoBoringSSL_X509_STORE_new()
            defer { CCryptoBoringSSL_X509_STORE_free(x509Store) }

            let x509StoreCtx = CCryptoBoringSSL_X509_STORE_CTX_new()
            defer { CCryptoBoringSSL_X509_STORE_CTX_free(x509StoreCtx) }

            // !-safe since certChain cannot be empty
            guard certChain.first!.withUnsafeMutablePointer({ CCryptoBoringSSL_X509_STORE_CTX_init(x509StoreCtx, x509Store, $0, x509Stack) }) == 1 else {
                return CertificatePolicyError.trustSetupFailure
            }
            CCryptoBoringSSL_X509_STORE_CTX_set_purpose(x509StoreCtx, X509_PURPOSE_ANY)

            anchorCerts.forEach { anchorCert in
                // add_cert returns 0 for all error types, including when we add duplicate cert, so we don't check for result > 0 here.
                // If an anchor cert didn't get added, trust evaluation should fail anyway.
                _ = anchorCert.withUnsafeMutablePointer { CCryptoBoringSSL_X509_STORE_add_cert(x509Store, $0) }
            }

            var ctxFlags: CInt = 0
            if let verifyDate {
                CCryptoBoringSSL_X509_STORE_CTX_set_time(x509StoreCtx, 0, numericCast(Int(verifyDate.timeIntervalSince1970)))
                ctxFlags = ctxFlags | X509_V_FLAG_USE_CHECK_TIME
            }
            CCryptoBoringSSL_X509_STORE_CTX_set_flags(x509StoreCtx, numericCast(UInt(ctxFlags)))

            let verifyCallback: BoringSSLVerifyCallback = { result, ctx in
                // Success
                if result == 1 { return result }

                // Custom error handling
                let errorCode = CCryptoBoringSSL_X509_STORE_CTX_get_error(ctx)
                // Certs could have unknown critical extensions and cause them to be rejected.
                // Check if they are tolerable.
                if errorCode == X509_V_ERR_UNHANDLED_CRITICAL_EXTENSION {
                    guard let ctx = ctx, let cert = CCryptoBoringSSL_X509_STORE_CTX_get_current_cert(ctx) else {
                        return result
                    }

                    let capacity = 100
                    let oidBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: capacity)
                    defer { oidBuffer.deallocate() }

                    for i in 0 ..< CCryptoBoringSSL_X509_get_ext_count(cert) {
                        let ext = CCryptoBoringSSL_X509_get_ext(cert, numericCast(i))
                        // Skip if extension is not critical or it is supported by BoringSSL
                        if CCryptoBoringSSL_X509_EXTENSION_get_critical(ext) <= 0 || CCryptoBoringSSL_X509_supported_extension(ext) > 0 { continue }

                        // Extract OID of the critical extension
                        let extObj = CCryptoBoringSSL_X509_EXTENSION_get_object(ext)
                        guard CCryptoBoringSSL_OBJ_obj2txt(oidBuffer, numericCast(capacity), extObj, numericCast(1)) > 0,
                            let oid = String(cString: oidBuffer, encoding: .utf8),
                            supportedCriticalExtensions.contains(oid) else {
                            return result
                        }
                    }
                    // No actual unhandled critical extension found, so trust the cert chain
                    return 1
                }
                return result
            }
            CCryptoBoringSSL_X509_STORE_CTX_set_verify_cb(x509StoreCtx, verifyCallback)

            guard CCryptoBoringSSL_X509_verify_cert(x509StoreCtx) == 1 else {
                let error = CCryptoBoringSSL_X509_verify_cert_error_string(numericCast(CCryptoBoringSSL_X509_STORE_CTX_get_error(x509StoreCtx)))
                observabilityScope.emit(warning: "The certificate is invalid: \(String(describing: error.flatMap { String(cString: $0, encoding: .utf8) }))")
                return CertificatePolicyError.invalidCertChain
            }

            return nil
        }

        if let error {
            return wrappedCallback(.failure(error))
        }

        if certChain.count > 1, let httpClient = httpClient {
            // Whether cert chain can be trusted depends on OCSP result
            ocspClient.checkStatus(certificate: certChain[0], issuer: certChain[1], anchorCerts: anchorCerts, httpClient: httpClient,
                                   callbackQueue: callbackQueue, callback: callback)
        } else {
            wrappedCallback(.success(()))
        }
    }
    #endif
}

#if os(Linux) || os(Windows) || os(Android)
private let ocspClient = BoringSSLOCSPClient()

private struct BoringSSLOCSPClient {
    private let resultCache = ThreadSafeKeyValueStore<CacheKey, CacheValue>()

    private let cacheTTL: DispatchTimeInterval

    init(cacheTTL: DispatchTimeInterval = .seconds(300)) {
        self.cacheTTL = cacheTTL
    }

    func checkStatus(certificate: Certificate,
                     issuer: Certificate,
                     anchorCerts: [Certificate]?,
                     httpClient: LegacyHTTPClient,
                     callbackQueue: DispatchQueue,
                     callback: @escaping (Result<Void, Error>) -> Void) {
        let wrappedCallback: (Result<Void, Error>) -> Void = { result in callbackQueue.async { callback(result) } }

        let ocspURLs = certificate.withUnsafeMutablePointer { CCryptoBoringSSL_X509_get1_ocsp($0) }
        defer { CCryptoBoringSSL_sk_OPENSSL_STRING_free(ocspURLs) }

        let ocspURLCount = CCryptoBoringSSL_sk_OPENSSL_STRING_num(ocspURLs)
        // Nothing to do if no OCSP URLs. Use `supportsOCSP` to require OCSP support if needed.
        guard ocspURLCount > 0 else { return wrappedCallback(.success(())) }

        // Construct the OCSP request
        let digest = CCryptoBoringSSL_EVP_sha1()
        let certid = certificate.withUnsafeMutablePointer { certPtr in
            issuer.withUnsafeMutablePointer { issPtr in
                OCSP_cert_to_id(digest, certPtr, issPtr)
            }
        }
        let request = OCSP_REQUEST_new()
        defer { OCSP_REQUEST_free(request) }

        guard OCSP_request_add0_id(request, certid) != nil else {
            return wrappedCallback(.failure(CertificatePolicyError.ocspSetupFailure))
        }

        // Write the request binary to memory bio
        let bio = CCryptoBoringSSL_BIO_new(CCryptoBoringSSL_BIO_s_mem())
        defer { CCryptoBoringSSL_BIO_free(bio) }
        guard i2d_OCSP_REQUEST_bio(bio, request) > 0 else {
            return wrappedCallback(.failure(CertificatePolicyError.ocspSetupFailure))
        }

        // Copy from bio to byte array then convert to Data
        var count = 0
        var out: UnsafePointer<UInt8>?
        guard CCryptoBoringSSL_BIO_mem_contents(bio, &out, &count) > 0 else {
            return wrappedCallback(.failure(CertificatePolicyError.ocspSetupFailure))
        }

        let requestData = Data(UnsafeBufferPointer(start: out, count: count))

        let results = ThreadSafeArrayStore<Result<Bool, Error>>()
        let group = DispatchGroup()

        // Query each OCSP responder and record result
        for index in 0 ..< ocspURLCount {
            guard let urlStr = CCryptoBoringSSL_sk_OPENSSL_STRING_value(ocspURLs, numericCast(index)),
                let url = String(validatingUTF8: urlStr).flatMap({ URL(string: $0) }) else {
                results.append(.failure(OCSPError.badURL))
                continue
            }

            let cacheKey = CacheKey(url: url, request: requestData)
            if let cachedResult = self.resultCache[cacheKey] {
                if cachedResult.timestamp + self.cacheTTL > DispatchTime.now() {
                    results.append(.success(cachedResult.isCertGood))
                    continue
                }
            }

            var headers = HTTPClientHeaders()
            headers.add(name: "Content-Type", value: "application/ocsp-request")
            guard let host = url.host else {
                results.append(.failure(OCSPError.badURL))
                continue
            }
            headers.add(name: "Host", value: host)

            var options = LegacyHTTPClientRequest.Options()
            options.validResponseCodes = [200]

            group.enter()
            httpClient.post(url, body: requestData, headers: headers, options: options) { result in
                switch result {
                case .failure:
                    // Try GET in case POST fails - the URL is OCSP URL + base64 encoded request
                    let encodedRequest = requestData.base64EncodedString()
                    httpClient.get(url.appendingPathComponent(encodedRequest)) { getResult in
                        defer { group.leave() }

                        switch getResult {
                        case .failure(let error):
                            results.append(.failure(error))
                        case .success(let response):
                            processResponse(response, cacheKey: cacheKey)
                        }
                    }
                case .success(let response):
                    defer { group.leave() }
                    processResponse(response, cacheKey: cacheKey)
                }
            }
        }

        group.notify(queue: callbackQueue) {
            // Fail open: As long as no one says the cert is revoked we assume it's ok. If we receive no responses or
            // all of them are failures we'd still assume the cert is not revoked.
            guard results.compactMap({ $0.success }).first(where: { !$0 }) == nil else {
                return wrappedCallback(.failure(CertificatePolicyError.invalidCertChain))
            }
            wrappedCallback(.success(()))
        }

        func processResponse(_ response: LegacyHTTPClient.Response, cacheKey: CacheKey) {
            guard let responseData = response.body else {
                results.append(.failure(OCSPError.emptyResponseBody))
                return
            }

            let bytes = responseData.copyBytes()

            // Convert response to bio then OCSP response
            let bio = CCryptoBoringSSL_BIO_new(CCryptoBoringSSL_BIO_s_mem())
            defer { CCryptoBoringSSL_BIO_free(bio) }
            guard CCryptoBoringSSL_BIO_write(bio, bytes, numericCast(bytes.count)) > 0 else {
                results.append(.failure(OCSPError.responseConversionFailure))
                return
            }

            let response = d2i_OCSP_RESPONSE_bio(bio, nil)
            defer { OCSP_RESPONSE_free(response) }

            guard let response else {
                results.append(.failure(OCSPError.responseConversionFailure))
                return
            }

            let basicResp = OCSP_response_get1_basic(response)
            defer { OCSP_BASICRESP_free(basicResp) }

            guard let basicResp else {
                results.append(.failure(OCSPError.responseConversionFailure))
                return
            }

            // This is just the OCSP response status, not the certificate's status
            guard OCSP_response_status(response) == OCSP_RESPONSE_STATUS_SUCCESSFUL,
                CCryptoBoringSSL_OBJ_obj2nid(response.pointee.responseBytes.pointee.responseType) == NID_id_pkix_OCSP_basic else {
                results.append(.failure(OCSPError.badResponse))
                return
            }

            let x509Store = CCryptoBoringSSL_X509_STORE_new()
            defer { CCryptoBoringSSL_X509_STORE_free(x509Store) }

            anchorCerts?.forEach { anchorCert in
                _ = anchorCert.withUnsafeMutablePointer { CCryptoBoringSSL_X509_STORE_add_cert(x509Store, $0) }
            }

            // Verify the OCSP response to make sure we can trust it
            guard OCSP_basic_verify(basicResp, nil, x509Store, 0) > 0 else {
                results.append(.failure(OCSPError.responseVerificationFailure))
                return
            }

            // Inspect the OCSP response
            let basicRespData = basicResp.pointee.tbsResponseData.pointee
            for i in 0 ..< sk_OCSP_SINGLERESP_num(basicRespData.responses) {
                guard let singleResp = sk_OCSP_SINGLERESP_value(basicRespData.responses, numericCast(i)),
                    let certStatus = singleResp.pointee.certStatus else {
                    results.append(.failure(OCSPError.badResponse))
                    return
                }

                // Is the certificate in good status?
                let isCertGood = certStatus.pointee.type == V_OCSP_CERTSTATUS_GOOD
                results.append(.success(isCertGood))
                self.resultCache[cacheKey] = CacheValue(isCertGood: isCertGood, timestamp: DispatchTime.now())
                break
            }
        }
    }

    private struct CacheKey: Hashable {
        let url: URL
        let request: Data
    }

    private struct CacheValue {
        let isCertGood: Bool
        let timestamp: DispatchTime
    }
}

private extension Result {
    var failure: Failure? {
        switch self {
        case .failure(let failure):
            return failure
        case .success:
            return nil
        }
    }

    var success: Success? {
        switch self {
        case .failure:
            return nil
        case .success(let value):
            return value
        }
    }
}

private extension LegacyHTTPClient {
    static func makeDefault(callbackQueue: DispatchQueue) -> LegacyHTTPClient {
        var httpClientConfig = LegacyHTTPClientConfiguration()
        httpClientConfig.callbackQueue = callbackQueue
        httpClientConfig.requestTimeout = .seconds(1)
        return LegacyHTTPClient(configuration: httpClientConfig)
    }
}
#endif

// MARK: - Supporting methods and types

extension CertificatePolicy {
    func hasExtension(oid: String, in certificate: Certificate) throws -> Bool {
        #if os(macOS)
        guard let dict = SecCertificateCopyValues(certificate.underlying, [oid as CFString] as CFArray, nil) as? [CFString: Any] else {
            throw CertificatePolicyError.extensionFailure
        }
        return !dict.isEmpty
        #elseif os(Linux) || os(Windows) || os(Android)
        let nid = CCryptoBoringSSL_OBJ_create(oid, "ObjectShortName", "ObjectLongName")
        let index = certificate.withUnsafeMutablePointer { CCryptoBoringSSL_X509_get_ext_by_NID($0, nid, -1) }
        return index >= 0
        #else
        fatalError("Unsupported: \(#function)")
        #endif
    }

    func hasExtendedKeyUsage(_ usage: CertificateExtendedKeyUsage, in certificate: Certificate) throws -> Bool {
        #if os(macOS)
        guard let dict = SecCertificateCopyValues(certificate.underlying, [kSecOIDExtendedKeyUsage] as CFArray, nil) as? [CFString: Any] else {
            throw CertificatePolicyError.extensionFailure
        }
        guard let usageDict = dict[kSecOIDExtendedKeyUsage] as? [CFString: Any],
            let usages = usageDict[kSecPropertyKeyValue] as? [Data] else {
            return false
        }
        return usages.first(where: { $0 == usage.data }) != nil
        #elseif os(Linux) || os(Windows) || os(Android)
        let eku = certificate.withUnsafeMutablePointer { CCryptoBoringSSL_X509_get_extended_key_usage($0) }
        return eku & UInt32(usage.flag) > 0
        #else
        fatalError("Unsupported: \(#function)")
        #endif
    }

    /// Checks that the certificate supports OCSP. This **must** be done before calling `verify` to ensure
    /// the necessary properties are in place to trigger revocation check.
    func supportsOCSP(certificate: Certificate) throws -> Bool {
        #if os(macOS)
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
        #elseif os(Linux) || os(Windows) || os(Android)
        // Check that there is at least one OCSP responder URL, in which case OCSP check will take place in `verify`.
        let ocspURLs = certificate.withUnsafeMutablePointer { CCryptoBoringSSL_X509_get1_ocsp($0) }
        defer { CCryptoBoringSSL_sk_OPENSSL_STRING_free(ocspURLs) }

        return CCryptoBoringSSL_sk_OPENSSL_STRING_num(ocspURLs) > 0
        #else
        fatalError("Unsupported: \(#function)")
        #endif
    }
}

enum CertificateExtendedKeyUsage {
    case codeSigning

    #if os(macOS)
    var data: Data {
        switch self {
        case .codeSigning:
            // https://stackoverflow.com/questions/49489591/how-to-extract-or-compare-ksecpropertykeyvalue-from-seccertificate
            // https://github.com/google/der-ascii/blob/cd91cb85bb0d71e4611856e4f76f5110609d7e42/cmd/der2ascii/oid_names.go#L100
            return Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x03])
        }
    }

    #elseif os(Linux) || os(Windows) || os(Android)
    var flag: CInt {
        switch self {
        case .codeSigning:
            // https://www.openssl.org/docs/man1.1.0/man3/X509_get_extension_flags.html
            return XKU_CODE_SIGN
        }
    }
    #endif
}

extension CertificatePolicy {
    static func loadCerts(at directory: URL, observabilityScope: ObservabilityScope) -> [Certificate] {
        var certs = [Certificate]()
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                do {
                    certs.append(try Certificate(derEncoded: Data(contentsOf: fileURL)))
                } catch {
                    observabilityScope.emit(warning: "The certificate \(fileURL) is invalid: \(error)")
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
    case unhandledCriticalException
    case noTrustedRootCertsConfigured
    case ocspSetupFailure
}

private enum OCSPError: Error {
    case badURL
    case emptyResponseBody
    case responseConversionFailure
    case badResponse
    case responseVerificationFailure
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

    #if os(Linux) || os(Windows) || os(Android)
    private let httpClient: LegacyHTTPClient
    #endif

    private let observabilityScope: ObservabilityScope

    /// Initializes a `DefaultCertificatePolicy`.
    /// - Parameters:
    ///   - trustedRootCertsDir: On Apple platforms, all root certificates that come preinstalled with the OS are automatically trusted.
    ///                          Users may specify additional certificates to trust by placing them in `trustedRootCertsDir` and
    ///                          configure the signing tool or SwiftPM to use it. On non-Apple platforms, only trust root certificates in
    ///                          `trustedRootCertsDir` are trusted.
    ///   - additionalTrustedRootCerts: Root certificates to be trusted in addition to those in `trustedRootCertsDir`. The difference
    ///                                 between this and `trustedRootCertsDir` is that the latter is user configured and dynamic,
    ///                                 while this is configured by SwiftPM and static.
    ///   - expectedSubjectUserID: The subject user ID that must match if specified.
    ///   - callbackQueue: The `DispatchQueue` to use for callbacks
    init(trustedRootCertsDir: URL?, additionalTrustedRootCerts: [Certificate]?, expectedSubjectUserID: String? = nil, observabilityScope: ObservabilityScope, callbackQueue: DispatchQueue) {
        #if !(os(macOS) || os(Linux) || os(Windows) || os(Android))
        fatalError("Unsupported: \(#function)")
        #else
        var trustedRoots = [Certificate]()
        if let trustedRootCertsDir {
            trustedRoots.append(contentsOf: Self.loadCerts(at: trustedRootCertsDir ,observabilityScope: observabilityScope))
        }
        if let additionalTrustedRootCerts {
            trustedRoots.append(contentsOf: additionalTrustedRootCerts)
        }
        self.trustedRoots = trustedRoots.isEmpty ? nil : trustedRoots
        self.expectedSubjectUserID = expectedSubjectUserID
        self.callbackQueue = callbackQueue

        #if os(Linux) || os(Windows) || os(Android)
        self.httpClient = LegacyHTTPClient.makeDefault(callbackQueue: callbackQueue)
        #endif
        #endif

        self.observabilityScope = observabilityScope
    }

    func validate(certChain: [Certificate], callback: @escaping (Result<Void, Error>) -> Void) {
        #if !(os(macOS) || os(Linux) || os(Windows) || os(Android))
        fatalError("Unsupported: \(#function)")
        #else
        let wrappedCallback: (Result<Void, Error>) -> Void = { result in self.callbackQueue.async { callback(result) } }

        guard !certChain.isEmpty else {
            return wrappedCallback(.failure(CertificatePolicyError.emptyCertChain))
        }

        do {
            // Check if subject user ID matches
            if let expectedSubjectUserID {
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
            #if os(macOS)
            self.verify(certChain: certChain, anchorCerts: self.trustedRoots, callbackQueue: self.callbackQueue, callback: callback)
            #elseif os(Linux) || os(Windows) || os(Android)
            self.verify(certChain: certChain, anchorCerts: self.trustedRoots, httpClient: self.httpClient, observabilityScope: self.observabilityScope, callbackQueue: self.callbackQueue, callback: callback)
            #endif
        } catch {
            return wrappedCallback(.failure(error))
        }
        #endif
    }
}

/// Policy for validating developer.apple.com Swift Package Collection certificates.
///
/// This has the same requirements as `DefaultCertificatePolicy` plus additional
/// marker extensions for Swift Package Collection certifiications.
struct AppleSwiftPackageCollectionCertificatePolicy: CertificatePolicy {
    private static let expectedCertChainLength = 3

    let trustedRoots: [Certificate]?
    let expectedSubjectUserID: String?

    private let callbackQueue: DispatchQueue

    #if os(Linux) || os(Windows) || os(Android)
    private let httpClient: LegacyHTTPClient
    #endif

    private let observabilityScope: ObservabilityScope

    /// Initializes a `AppleSwiftPackageCollectionCertificatePolicy`.
    /// - Parameters:
    ///   - trustedRootCertsDir: On Apple platforms, all root certificates that come preinstalled with the OS are automatically trusted.
    ///                          Users may specify additional certificates to trust by placing them in `trustedRootCertsDir` and
    ///                          configure the signing tool or SwiftPM to use it. On non-Apple platforms, only trust root certificates in
    ///                          `trustedRootCertsDir` are trusted.
    ///   - additionalTrustedRootCerts: Root certificates to be trusted in addition to those in `trustedRootCertsDir`. The difference
    ///                                 between this and `trustedRootCertsDir` is that the latter is user configured and dynamic,
    ///                                 while this is configured by SwiftPM and static.
    ///   - expectedSubjectUserID: The subject user ID that must match if specified.
    ///   - callbackQueue: The `DispatchQueue` to use for callbacks
    init(trustedRootCertsDir: URL?, additionalTrustedRootCerts: [Certificate]?, expectedSubjectUserID: String? = nil, observabilityScope: ObservabilityScope, callbackQueue: DispatchQueue) {
        #if !(os(macOS) || os(Linux) || os(Windows) || os(Android))
        fatalError("Unsupported: \(#function)")
        #else
        var trustedRoots = [Certificate]()
        if let trustedRootCertsDir {
            trustedRoots.append(contentsOf: Self.loadCerts(at: trustedRootCertsDir, observabilityScope: observabilityScope))
        }
        if let additionalTrustedRootCerts {
            trustedRoots.append(contentsOf: additionalTrustedRootCerts)
        }
        self.trustedRoots = trustedRoots.isEmpty ? nil : trustedRoots
        self.expectedSubjectUserID = expectedSubjectUserID
        self.callbackQueue = callbackQueue

        #if os(Linux) || os(Windows) || os(Android)
        self.httpClient = LegacyHTTPClient.makeDefault(callbackQueue: callbackQueue)
        #endif
        #endif

        self.observabilityScope = observabilityScope
    }

    func validate(certChain: [Certificate], callback: @escaping (Result<Void, Error>) -> Void) {
        #if !(os(macOS) || os(Linux) || os(Windows) || os(Android))
        fatalError("Unsupported: \(#function)")
        #else
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
            if let expectedSubjectUserID {
                guard try certChain[0].subject().userID == expectedSubjectUserID else {
                    return wrappedCallback(.failure(CertificatePolicyError.subjectUserIDMismatch))
                }
            }

            // Check marker extension
            guard try self.hasExtension(oid: appleSwiftPackageCollectionMarker, in: certChain[0]) else {
                return wrappedCallback(.failure(CertificatePolicyError.missingRequiredExtension))
            }
            guard try self.hasAppleIntermediateMarker(certificate: certChain[1]) else {
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
            #if os(macOS)
            self.verify(certChain: certChain, anchorCerts: self.trustedRoots, callbackQueue: self.callbackQueue, callback: callback)
            #elseif os(Linux) || os(Windows) || os(Android)
            self.verify(certChain: certChain, anchorCerts: self.trustedRoots, httpClient: self.httpClient, observabilityScope: self.observabilityScope, callbackQueue: self.callbackQueue, callback: callback)
            #endif
        } catch {
            return wrappedCallback(.failure(error))
        }
        #endif
    }
}

/// Policy for validating developer.apple.com Apple Distribution certificates.
///
/// This has the same requirements as `DefaultCertificatePolicy` plus additional
/// marker extensions for Apple Distribution certifiications.
struct AppleDistributionCertificatePolicy: CertificatePolicy {
    private static let expectedCertChainLength = 3

    let trustedRoots: [Certificate]?
    let expectedSubjectUserID: String?

    private let callbackQueue: DispatchQueue

    #if os(Linux) || os(Windows) || os(Android)
    private let httpClient: LegacyHTTPClient
    #endif

    private let observabilityScope: ObservabilityScope

    /// Initializes a `AppleDistributionCertificatePolicy`.
    /// - Parameters:
    ///   - trustedRootCertsDir: On Apple platforms, all root certificates that come preinstalled with the OS are automatically trusted.
    ///                          Users may specify additional certificates to trust by placing them in `trustedRootCertsDir` and
    ///                          configure the signing tool or SwiftPM to use it. On non-Apple platforms, only trust root certificates in
    ///                          `trustedRootCertsDir` are trusted.
    ///   - additionalTrustedRootCerts: Root certificates to be trusted in addition to those in `trustedRootCertsDir`. The difference
    ///                                 between this and `trustedRootCertsDir` is that the latter is user configured and dynamic,
    ///                                 while this is configured by SwiftPM and static.
    ///   - expectedSubjectUserID: The subject user ID that must match if specified.
    ///   - callbackQueue: The `DispatchQueue` to use for callbacks
    init(trustedRootCertsDir: URL?, additionalTrustedRootCerts: [Certificate]?, expectedSubjectUserID: String? = nil, observabilityScope: ObservabilityScope, callbackQueue: DispatchQueue) {
        #if !(os(macOS) || os(Linux) || os(Windows) || os(Android))
        fatalError("Unsupported: \(#function)")
        #else
        var trustedRoots = [Certificate]()
        if let trustedRootCertsDir {
            trustedRoots.append(contentsOf: Self.loadCerts(at: trustedRootCertsDir, observabilityScope: observabilityScope))
        }
        if let additionalTrustedRootCerts {
            trustedRoots.append(contentsOf: additionalTrustedRootCerts)
        }
        self.trustedRoots = trustedRoots.isEmpty ? nil : trustedRoots
        self.expectedSubjectUserID = expectedSubjectUserID
        self.callbackQueue = callbackQueue

        #if os(Linux) || os(Windows) || os(Android)
        self.httpClient = LegacyHTTPClient.makeDefault(callbackQueue: callbackQueue)
        #endif
        #endif

        self.observabilityScope = observabilityScope
    }

    func validate(certChain: [Certificate], callback: @escaping (Result<Void, Error>) -> Void) {
        #if !(os(macOS) || os(Linux) || os(Windows) || os(Android))
        fatalError("Unsupported: \(#function)")
        #else
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
            if let expectedSubjectUserID {
                guard try certChain[0].subject().userID == expectedSubjectUserID else {
                    return wrappedCallback(.failure(CertificatePolicyError.subjectUserIDMismatch))
                }
            }

            // Check marker extensions (certificates issued post WWDC 2019 have both extensions but earlier ones have just one depending on platform)
            guard try (self.hasExtension(oid: appleDistributionIOSMarker, in: certChain[0]) || self.hasExtension(oid: appleDistributionMacOSMarker, in: certChain[0])) else {
                return wrappedCallback(.failure(CertificatePolicyError.missingRequiredExtension))
            }
            guard try self.hasAppleIntermediateMarker(certificate: certChain[1]) else {
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
            #if os(macOS)
            self.verify(certChain: certChain, anchorCerts: self.trustedRoots, callbackQueue: self.callbackQueue, callback: callback)
            #elseif os(Linux) || os(Windows) || os(Android)
            self.verify(certChain: certChain, anchorCerts: self.trustedRoots, httpClient: self.httpClient, observabilityScope: self.observabilityScope, callbackQueue: self.callbackQueue, callback: callback)
            #endif
        } catch {
            return wrappedCallback(.failure(error))
        }
        #endif
    }
}

extension CertificatePolicy {
    func hasAppleIntermediateMarker(certificate: Certificate) throws -> Bool {
        var extensionError: Error?
        for marker in appleIntermediateMarkers {
            do {
                if try self.hasExtension(oid: marker, in: certificate) {
                    return true
                }
            } catch {
                extensionError = error
            }
        }

        if let extensionError {
            throw extensionError
        }
        return false
    }
}

public enum CertificatePolicyKey: Hashable, CustomStringConvertible {
    case `default`(subjectUserID: String?)
    case appleSwiftPackageCollection(subjectUserID: String?)
    case appleDistribution(subjectUserID: String?)

    /// For internal-use only
    case custom

    public var description: String {
        switch self {
        case .default(let subject):
            return "Default certificate policy\(subject.map { " (subject: \($0))" } ?? "")"
        case .appleSwiftPackageCollection(let subject):
            return "Swift Package Collection certificate policy\(subject.map { " (subject: \($0))" } ?? "")"
        case .appleDistribution(let subject):
            return "Distribution certificate policy\(subject.map { " (subject: \($0))" } ?? "")"
        case .custom:
            return "Custom certificate policy"
        }
    }

    public static let `default` = CertificatePolicyKey.default(subjectUserID: nil)
    public static let appleSwiftPackageCollection = CertificatePolicyKey.appleSwiftPackageCollection(subjectUserID: nil)
    public static let appleDistribution = CertificatePolicyKey.appleDistribution(subjectUserID: nil)
}
