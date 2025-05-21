# Publishing package collections

Learn how to publish package collections.

## Overview

Package collections can be created and published by anyone. The [swift-package-collection-generator](https://github.com/apple/swift-package-collection-generator) project provides tooling 
intended for package collection publishers:
- [`package-collection-generate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionGenerator): Generate a package collection given a list of package URLs
- [`package-collection-sign`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionSigner): Sign a package collection
- [`package-collection-validate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionValidator): Perform basic validations on a package collection
- [`package-collection-diff`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionDiff): Compare two package collections to see if their contents are different 

<!-- 
### Creating package collections

All package collections must adhere to the [collection data format](<doc:PackageCollectionCreationGuide>) for SwiftPM to be able to consume them. The recommended way
to create package collections is to use [`package-collection-generate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionGenerator). For custom implementations, the data models are available through the [`PackageCollectionsModel` module](https://github.com/swiftlang/swift-package-manager/tree/main/Sources/PackageCollectionsModel).

### Package collection signing (optional)

Package collections can be signed to establish authenticity and protect their integrity. Doing this is optional. Users will be prompted for confirmation before they can add an [unsigned collection](<doc:PackageCollectionSigning#Unsigned-package-collections>).

[`package-collection-sign`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionSigner) helps publishers sign their package 
collections. To generate a signature one must provide:
- The package collection file to be signed
- A code signing certificate (DER-encoded)
- The certificate's private key (PEM-encoded)
- The certificate's chain in its entirety

A signed package collection has an extra `signature` object:

```json
{
  ...,
  "signature": {
    "signature": "<SIGNATURE>",
    "certificate": {
      "subject": {
        "commonName": "Jane Doe",
        ...
      },
      "issuer": {
        "commonName": "Sample CA",
        ...
      }
    }
  }
}
```

- The signature string (represented by `"<SIGNATURE>"`) is used to verify the contents of the collection file haven't been tampered with since it was signed when SwiftPM user [adds the collection](#signed-package-collections) to their configured list of collections. It includes the certificate's public key and chain.
- `certificate` contains details extracted from the signing certificate. `subject.commonName` should be consistent with the name of the publisher so that it's recognizable by users. The root of the certificate must be [installed and trusted on users' machines](#trusted-root-certificates). 

#### Requirements on signing certificate

Certificates used for signing package collections must meet the following requirements, which are checked and enforced during signature generation (publishers) and verification (SwiftPM users):
- The timestamp at which signing/verification is done must fall within the signing certificate's validity period.
- The certificate's "Extended Key Usage" extension must include "Code Signing".
- The certificate must use either 256-bit EC (recommended for enhanced security) or 2048-bit RSA key.
- The certificate must not be revoked. The certificate authority must support OCSP, which means the certificate must have the "Certificate Authority Information Access" extension that includes OCSP as a method, specifying the responder's URL.
- The certificate chain is valid and root certificate must be trusted.

Non-expired, non-revoked Swift Package Collection certificates from [developer.apple.com](https://developer.apple.com) satisfy all of the criteria above.

##### Trusted root certificates

With the `package-collection-sign` tool, the root certificate provided as input for signing a collection is automatically trusted. When SwiftPM user tries to add the collection, however,
the root certificate must either be preinstalled with the OS (Apple platforms only) or found in the `~/.swiftpm/config/trust-root-certs` directory (all platforms) or shipped with 
the [certificate-pinning configuration](<doc:PackageCollectionSigning#Protecting-package-collections>), otherwise the [signature check](<doc:PackageCollectionAddGuide#Signed-package-collections>) will fail. Collection publishers should make the DER-encoded 
root certificate(s) that they use downloadable so that users can adjust their setup if needed.

### Protecting package collections

[Signing](#package-collection-signing-optional) can provide some degree of protection on package collections and reduce the risks of their contents being modified by malicious actors, but it doesn't
prevent the following attack vectors:
- **Signature stripping**: This involves attackers removing signature from a signed collection, causing it to be downloaded as an [unsigned collection](#unsigned-package-collections) and bypassing signature check. In this case, publishers should make it known that the collection is signed, and SwiftPM users should abort the `add` operation when the "unsigned" warning appears on a supposedly signed collection.
- **Signature replacement**: Attackers may modify a collection then re-sign it using a different certificate, either pretend to be the same entity or as some other entity, and SwiftPM will accept it as long as the [signature is valid](#signed-package-collections).

To defend against these attacks, SwiftPM has certificate-pinning configuration that allows collection publishers to:
- Require signature check on their collections — this defends against "signature stripping".
- Restrict what certificate can be used for signing — this defends against "signature replacement".

The process for collection publishers to define their certificate-pinning configuration is as follows:
1. Edit [`PackageCollectionSourceCertificatePolicy`](../Sources/PackageCollections/PackageCollections+CertificatePolicy.swift) and add an entry to the `defaultSourceCertPolicies` dictionary:

```swift
private static let defaultSourceCertPolicies: [String: CertificatePolicyConfig] = [
    // The key should be the "host" component of the package collection URL.
    // This would require all package collections hosted on this domain to be signed.
    "www.example.com": CertificatePolicyConfig(
        // The signing certificate must have this subject user ID
        certPolicyKey: CertificatePolicyKey.default(subjectUserID: "exampleUserID"),
        /*
         To compute base64-encoded string of a certificate:
         let certificateURL = URL(fileURLWithPath: <path to DER-encoded root certificate file>)
         let certificateData = try Data(contentsOf: certificateURL)
         let base64EncoodedCertificate = certificateData.base64EncodedString()
         */
        base64EncodedRootCerts: ["<base64-encoded root certificate>"]
    )
]
```

2. Open a pull request for review. The requestor must be able to provide proof of their identity and ownership on the domain:
    - The requestor must provide the actual certificate files (DER-encoded). The SwiftPM team will verify that the certificate chain is valid and the values provided in the PR are correct.
    - The requestor must add a TXT record referencing the pull request. The SwiftPM team will run `dig -t txt <DOMAIN>` to verify. This would act as proof of domain ownership.
3. After the changes are accepted, they will take effect in the next SwiftPM release.

Since certificate-pinning configuration is associated with web domains, it can only be applied to signed collections hosted on the web (i.e., URL begins with  `https://`) and does 
not cover those found on local file system (i.e., URL begins with `file://`). 
-->
