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

import Basics
import Dispatch
import Foundation
@testable import PackageCollectionsSigning
import TSCBasic
import XCTest

// Set `REAL_CERT_USER_ID` env var when running ENABLE_REAL_CERT_TEST tests
let expectedSubjectUserID = ProcessInfo.processInfo.environment["REAL_CERT_USER_ID"] ?? "<USER ID>"

let callbackQueue = DispatchQueue(label: "org.swift.swiftpm.PackageCollectionsSigningTests", attributes: .concurrent)

// MARK: - CertificatePolicy for test certs

struct TestCertificatePolicy: CertificatePolicy {
    static let testCertValidDate: Date = {
        // This is the datetime that the tests use to validate test certs (Test_rsa.cer, Test_ec.cer).
        // Make sure it falls within the certs' validity period, across timezones.
        // For example, suppose the current date is April 12, 2021, the cert validation runs as if
        // the date were July 18, 2021.
        var dateComponents = DateComponents()
        dateComponents.year = 2021
        dateComponents.month = 7
        dateComponents.day = 18
        return Calendar.current.date(from: dateComponents)!
    }()

    static let testCertInvalidDate: Date = {
        var dateComponents = DateComponents()
        dateComponents.year = 2000
        dateComponents.month = 11
        dateComponents.day = 16
        return Calendar.current.date(from: dateComponents)!
    }()

    let anchorCerts: [Certificate]?
    let verifyDate: Date

    init(anchorCerts: [Certificate]? = nil, verifyDate: Date = Self.testCertValidDate) {
        self.anchorCerts = anchorCerts
        self.verifyDate = verifyDate
    }

    func validate(certChain: [Certificate], callback: @escaping (Result<Void, Error>) -> Void) {
        do {
            guard try self.hasExtendedKeyUsage(.codeSigning, in: certChain[0]) else {
                return callbackQueue.async { callback(.failure(CertificatePolicyError.codeSigningCertRequired)) }
            }

            #if os(macOS)
            self.verify(certChain: certChain, anchorCerts: self.anchorCerts, verifyDate: self.verifyDate,
                        callbackQueue: callbackQueue, callback: callback)
            #else
            self.verify(certChain: certChain, anchorCerts: self.anchorCerts, verifyDate: self.verifyDate, httpClient: nil,
                        observabilityScope: ObservabilitySystem.NOOP,
                        callbackQueue: callbackQueue, callback: callback)
            #endif
        } catch {
            return callbackQueue.async { callback(.failure(error)) }
        }
    }
}

// MARK: - Test keys

let ecPrivateKey = """
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIMFnwA1gjIFnFZim4B2QvoXJIG2L4B8nH1BBZFlotA24oAoGCCqGSM49
AwEHoUQDQgAEkc2FgXZVz9llhV6+jAGPVHEcxBxK5tui9HWzvtE+ogKPr7i3e2JO
Xwm91hecppS11y/S8bLmrFxA+dCP/V7bnw==
-----END EC PRIVATE KEY-----
"""

let ecPublicKey = """
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEkc2FgXZVz9llhV6+jAGPVHEcxBxK
5tui9HWzvtE+ogKPr7i3e2JOXwm91hecppS11y/S8bLmrFxA+dCP/V7bnw==
-----END PUBLIC KEY-----
"""

let rsaPrivateKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEAoQIWz/MQ+mRShQxxxs+zlCLHRz+R1zUPKZhg3eggbXartfyI
OSPEDaVANCjE1QLg0dtGCpkbMAVQLkC7os5ZuW6A6qtSAU6WUBOvnDBPVumqmDUq
AeXGEQyDZqReRm3D4Ov4qOTlIk34pRhoCymaNTiw7GfyzzWOcPxcRGGTz6fv1gmS
wDnURBeL9QUAb2/sdAAsY/SZzziNF+womF8y3mn+IvlKL3EhtSxUfdZpPdFmxPza
oVIlllFQcKnxH4/0PZeyPK0Npq4kCqATXcYXmaa3Ms9tPcsQUggtAR/QepyrKmB1
SRAouHqKi+bGTlCpFSFbDgW422gfqXEEboh39QIDAQABAoIBAQCRUR9hxFHYjF9m
MhsmgyPjWZhel+N7RypOMneLEQzjfy3vbONOHxe98R4HdZxhXN2oyq1mt1UwfDsn
48j2YiPdFv1H0CSNhW5pC7t9zqRtHyyXf7RQTh/8Fz0pkMR98GfQQ2oElcKwuYrn
ByYwnPXPf0E/vXoKxp2vIDXuidssmUl37mvbyppGaVl+Is6GmAiZkNOKN8ZEXPvz
4BivJ3yhs/RiM5RUF93qj8j/3P6R8rXLemAE9jrKjGG7Vv966p1Fh9+wNnnnbT8t
zLDUVwD7Q/JERr+3Wdecp+pZIfWTvJJhE8R3IM4WrLQNeUEKo7YovfYA7rah3gP/
ixM2BM5pAoGBAM5+c7Sxl7hzII2yPxN2fIslyKw3E8HP1nnqUPUegFsU3TZRQUnZ
gm5JgQRPqFYy6fwouL07KdSb/zIes3ra/qkhaOewHsAvvvxKKM6FGqYrkb5BKv0s
gF/m4qg6GLSW3BVb/QfnwHdWE7z7KPGuomzg+pqshxTyKYkGN2l8IIu7AoGBAMeb
81636nRy62CYQhNCp13wqmmUJ8/VnNj2jdwdXQ5vlgQdrwFm2p52cEFn/AhL5WIn
GShRLKL/keK71tsD0hCsTuZISR1xFiFk0TFmjxSX+z2D9VGvSECtNfySRuroKorS
xIXsrx6dvk/Ef54yDus1O5vvdT3l6vSDbVJESFgPAoGBAIAFJ8kT/YNOZRVUOATi
Ba7jGvmiH+6d41OscMq3QU62rbr6P2cAofusOH+qvyvJ3wUFXht7raBxopK5M/7r
/MxwuTBDIZ13PIn/lDMNlIsHIhF5J6TUzTYn18gCVMTJbuMTJ9mZ1dpmlFAqyqSj
53FnPhdc9VaIGDYqk3ojia33AoGAd52bzNH3vMq1BJCZYANcWm4DIPu4k9JViKrP
Pe2WuzThOBw1qGhjb/xXrspKfQpGLnhxmfhzAEaYvL+FtH9onbc0HMmKjwsakO5i
cfEcouGknCt8kfOxH5jstitONizkeYZuYDcChh1PU2vUcg9bY1XmH77yiiJClz4+
/8KNe78CgYEArTT+XVctYq5jaFCtGqq3DD/DrgJeWS6V5Op0QgVrVKFeCH2mImOg
6+95qwqyl3xCTJNvLwcNB+yricsWfUicEPKfDJX1w8m5/fANMRZYXr2nmAZvS9Kw
pkG0a65+K/m4wnZIszEuNZ2ybjrHEwYdWygRkJUmHp5rzmjdKjCBkwU=
-----END RSA PRIVATE KEY-----
"""

let rsaPublicKey = """
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoQIWz/MQ+mRShQxxxs+z
lCLHRz+R1zUPKZhg3eggbXartfyIOSPEDaVANCjE1QLg0dtGCpkbMAVQLkC7os5Z
uW6A6qtSAU6WUBOvnDBPVumqmDUqAeXGEQyDZqReRm3D4Ov4qOTlIk34pRhoCyma
NTiw7GfyzzWOcPxcRGGTz6fv1gmSwDnURBeL9QUAb2/sdAAsY/SZzziNF+womF8y
3mn+IvlKL3EhtSxUfdZpPdFmxPzaoVIlllFQcKnxH4/0PZeyPK0Npq4kCqATXcYX
maa3Ms9tPcsQUggtAR/QepyrKmB1SRAouHqKi+bGTlCpFSFbDgW422gfqXEEboh3
9QIDAQAB
-----END PUBLIC KEY-----
"""

let certECPrivateKey = """
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIFyZDwhGj2Q6ZchEt6DIQSptRk9yKPo60JH5x4u3p4YmoAoGCCqGSM49
AwEHoUQDQgAEHg58TCXScU6zXSYygCNW0tBZeYFRWf3XAjaDJUkeEFUvKxiIcP8S
sLfb8P9mukwJsj2CwfatwneFIUQGJ4P+SQ==
-----END EC PRIVATE KEY-----
"""

let certRSAPrivateKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAk1a/7/deGbDnbe9K8/LzN7fkx4D0kzCHIBlCuSylKOJKiPQ5
MHH13IXAKJYbudkufYdbACTo/4xjgvWLWI/C/ycbNfEGTPd0r6ahS9LRljgGaCVr
eK4Jqg4VHIuC5B2fTQ5Tuv4k16JhKXuD/hCZ1my96Xwt2HPniRu9cIJFxlAz/1Fj
botlL6EbUzzZ7msNLdXEm7QWUIuCN48z1FKk/uapAewzjq1r3X4+pWmEJSi+2tyS
5K03bmH+SE63fBui6o4dzeCrOblGQxqyqnR0mHOKe5rHU8Y5LVmkam/wyiRGTrmT
OywsDhRtTyI0EZEp194C7QdLxiksGnl0wt/ArQIDAQABAoIBAG/1AD4QwrFU6lZv
+Y1rNANHuhEa3T2nJ1Ztu3TIBuwNH8P3iClWvxMFkyGEBqdu71O1caGnamEcxVTy
ziLKgsqtZZDUiAweEM2UGYZrOJUkF0I2BPcbj/5nWwVowVojZDQCSf+SNF6iZaBG
2eJJrQvxb1Gm6ZNLZ0mZCZcfdnOcwOwubGYGjoJV7qXRhs4kCfZMmA7g8MkQ0FBu
3fLmD2MMjWqJA2kgnYVf27BfoZrEJBfWSAQ5SKOeSnH7UqTF+L/HTrXJJnpjIY5i
Xr/+lJ7BiOHHouP8dwbggjCmkrcGwcwE7PULyhycty5DOnSpGT2ktElyeqivxPVl
Nqm3U+ECgYEAw8bsQrYrZoSGsmUBFQ29z+S402TJyTOF14PinkfEyF2Gmel0024A
1pY7eTrmlHJMBooy4IgdkLjKnaFMd98H+jcOpfX7dXXE+cCLAs9CA3HCeP5hsOl/
PduswEahqne58v/FcGDdc66Jf6bCb3sOcIku4vxKiInbbtv8hjvpCcUCgYEAwKlp
KQZ072QP4cNil+ITZjlf5xhihHUudL6BLfiR3BxQhtDqk/23rbEB69yl5JkSoYA8
4T86Gdhnfe6lKHmWbgBN54tcoaesH8yKfTFvZZfbhENfV0gxXXpxdvjM1/1peRVK
0CJsDAEvyREKhD4nuWv50vqMBK+HjD9gYANNEckCgYBbCMKPernPn8wqY8EPEyax
5r7yvSj/P8/6mL7lrqWYLbULGH1UWxBUt+LLylGxsTwcxmJF+cUVqHe+uGQgUTsa
ZEORdEILKkn/gEKjedBOXbV6IX83jju2fdFkTvOZmraCgeBDEyemRQB2tQowYF4k
ggWlUn8t4jyA3hYcLPt9qQKBgQCDIsyxX/O3/iPRR2yUdQ0/R04/vhlQj3JPhFvp
LogZiixFl24TzV54m0Lzh/xi3M4Rn3fQ2XhynxnSXd2M7zW1Kf/c2r7ySW6fNloN
XNi2Decc377Fah4vwmf40uCbI6HnCNcjVEq24Rflg/Pkj2n6i8RAFsm3ZsKcc4bl
01liAQKBgBTPtA4M3/TpKDwuPedsmzumSe1Rmn4QSAd0ssrQ9XoPHYw2RkBSpCQg
1HYM/lD21uBr66nAtqpByiNILTQm1LiitBSnC9jOjpoM+ECqMyYPwfU9AD7weYlX
qjLG9mzvjAEa7bzjweN77Mox4LDf6rEiAcs9ObceElEwN8W1g+63
-----END RSA PRIVATE KEY-----
"""

// MARK: - Utils

extension String {
    var bytes: [UInt8] {
        [UInt8](self.utf8)
    }
}

extension XCTestCase {
    func skipIfUnsupportedPlatform() throws {
        #if os(macOS) || os(Linux) || os(Windows) || os(Android)
        #else
        throw XCTSkip("Skipping test on unsupported platform")
        #endif
    }
}
