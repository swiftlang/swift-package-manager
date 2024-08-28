# Package Collections

Package collections, introduced by [SE-0291](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0291-package-collections.md), are
curated lists of packages and associated metadata that make discovery of existing packages easier. They are authored as static JSON documents 
and can be published to the web or distributed to local file systems. 

## Table of Contents

- [Using package collections with the `package-collection` CLI](#using-package-collections)
  - [`add` subcommand](#add-subcommand)
    - [Add signed package collections](#signed-package-collections)
      - [Configure trusted root certificates](#trusted-root-certificates)
    - [Add unsigned package collections](#unsigned-package-collections)
  - [`describe` subcommand](#describe-subcommand)
    - [Describe a package collection](#metadata-and-packages-of-a-collection)
    - [Describe a package](#metadata-of-a-package)
    - [Describe a package version](#metadata-of-a-package-version)
  - [`list` subcommand](#list-subcommand)
  - [`refresh` subcommand](#refresh-subcommand)
  - [`remove` subcommand](#remove-subcommand)
  - [`search` subcommand](#search-subcommand)
    - [Keyword search](#string-based-search)
    - [Module search](#module-based-search)
- [Package collection configuration](#configuration-file)
- [Publishing package collections](#publishing-package-collections)
  - [Creating package collections](#creating-package-collections)
  - [Signing package collections](#package-collection-signing-optional)
  - [Protecting package collections](#protecting-package-collections)

## Using package collections

With the `swift package-collection` command-line interface, SwiftPM users can subscribe to package collections. Contents of imported package 
collections are accessible to any clients of [libSwiftPM](libSwiftPM.md).

`swift package-collection` has the following subcommands:
- [`add`](#add-subcommand): Add a new collection
- [`describe`](#describe-subcommand): Get metadata for a collection or a package included in an imported collection
- [`list`](#list-subcommand): List configured collections
- [`refresh`](#refresh-subcommand): Refresh configured collections
- [`remove`](#remove-subcommand): Remove a configured collection
- [`search`](#search-subcommand): Search for packages by keywords or module names within imported collections

### `add` subcommand

This subcommand adds a package collection hosted on the web (HTTPS required):

```bash
$ swift package-collection add https://www.example.com/packages.json
Added "Sample Package Collection" to your package collections.
```

Or found in the local file system:

```bash
$ swift package-collection add file:///absolute/path/to/packages.json
Added "Sample Package Collection" to your package collections.
```

The optional `order` hint can be used to order collections and may potentially influence ranking in search results:

```bash
$ swift package-collection add https://www.example.com/packages.json [--order N]
Added "Sample Package Collection" to your package collections.
```

#### Signed package collections

Package collection publishers may sign a collection to protect its contents from being tampered with. If a collection is signed, SwiftPM will check that the 
signature is valid before importing it and return an error if any of these fails:
- The file's contents, signature excluded, must match what was used to generate the signature. In other words, this checks to see if the collection has been altered since it was signed.
- The signing certificate must meet all the [requirements](#requirements-on-signing-certificate).

```bash
$ swift package-collection add https://www.example.com/bad-packages.json
The collection's signature is invalid. If you would like to continue please rerun command with '--skip-signature-check'.
```

Users may continue adding the collection despite the error or preemptively skip the signature check on a package collection by passing the `--skip-signature-check` flag:

```bash
$ swift package-collection add https://www.example.com/packages.json --skip-signature-check
```

For package collections hosted on the web, publishers may ask SwiftPM to [enforce the signature requirement](#protecting-package-collections). If a package collection is
expected to be signed but it isn't, user will see the following error message:

```bash
$ swift package-collection add https://www.example.com/bad-packages.json
The collection is missing required signature, which means it might have been compromised.
```

Users should NOT add the package collection in this case.

##### Trusted root certificates

Since generating a collection signature requires a certificate, part of the signature check involves validating the certificate and its chain and making sure that the root certificate is trusted.

On Apple platforms, all root certificates that come preinstalled with the OS are automatically trusted. Users may include additional certificates to trust by placing 
them in the `~/.swiftpm/config/trust-root-certs` directory. 

On non-Apple platforms, there are no trusted root certificates by default other than those shipped with the [certificate-pinning configuration](#protecting-package-collections). Only those 
found in `~/.swiftpm/config/trust-root-certs` are trusted. This means that the signature check will always fail unless the `trust-root-certs` directory is set up:

```bash
$ swift package-collection add https://www.example.com/packages.json
The collection's signature cannot be verified due to missing configuration.
```

Users can explicitly specify they trust a publisher and any collections they publish, by obtaining that publisher's root certificate and saving it to `~/.swiftpm/config/trust-root-certs`. The 
root certificates must be DER-encoded. Since SwiftPM trusts all certificate chains under a root, depending on what roots are installed, some publishers may already be trusted implicitly and 
users don't need to explicitly specify each one. 

#### Unsigned package collections

Users will get an error when trying to add an unsigned package collection:

```bash
$ swift package-collection add https://www.example.com/packages.json
The collection is not signed. If you would still like to add it please rerun 'add' with '--trust-unsigned'.
```

To continue user must confirm their trust by passing the `--trust-unsigned` flag:

```bash
$ swift package-collection add https://www.example.com/packages.json --trust-unsigned
```

The `--skip-signature-check` flag has no effects on unsigned collections.

### `describe` subcommand

This subcommand shows metadata for a collection or a package included in an imported collection. The result can optionally be returned as JSON using `--json` for
integration into other tools.

#### Metadata and packages of a collection

`describe` can be used for both collections that have been previously added to the list of the user's configured collections, as well as to preview any other collections.

```bash
$ swift package-collection describe [--json] https://www.example.com/packages.json
Name: Sample Package Collection
Source: https://www.example.com/packages.json
Description: ...
Keywords: best, packages
Created At: 2020-05-30 12:33
Packages:
    https://github.com/jpsim/yams
    ...
```

##### Signed package collections

If a collection is signed, SwiftPM will check that the signature is valid before showing a preview.

```bash
$ swift package-collection describe https://www.example.com/bad-packages.json
The collection's signature is invalid. If you would like to continue please rerun command with '--skip-signature-check'.
```

Users may continue previewing the collection despite the error or preemptively skip the signature check on a package collection by passing the `--skip-signature-check` flag:

```bash
$ swift package-collection describe https://www.example.com/packages.json --skip-signature-check
```

#### Metadata of a package

`describe` can also show the metadata of a package included in an imported collection:

```bash
$ swift package-collection describe [--json] https://github.com/jpsim/yams
Description: A sweet and swifty YAML parser built on LibYAML.
Available Versions: 4.0.0, 3.0.0, ...
Stars: 14
Readme: https://github.com/jpsim/Yams/blob/master/README.md
Authors: @norio-nomura, @jpsim
--------------------------------------------------------------
Latest Version: 4.0.0
Package Name: Yams
Modules: Yams, CYaml
Supported Platforms: iOS, macOS, Linux, tvOS, watchOS
Supported Swift Versions: 5.3, 5.2, 5.1, 5.0
License: MIT
```

#### Metadata of a package version

User may view additional metadata for a package version by passing `--version`:

```bash
$ swift package-collection describe [--json] --version 4.0.0 https://github.com/jpsim/yams
Package Name: Yams
Version: 4.0.0
Modules: Yams, CYaml
Supported Platforms: iOS, macOS, Linux, tvOS, watchOS
Supported Swift Versions: 5.3, 5.2, 5.1, 5.0
License: MIT
```

### `list` subcommand

This subcommand lists all collections that are configured by the user:

```bash
$ swift package-collection list [--json]
Sample Package Collection - https://example.com/packages.json
...
```

The result can optionally be returned as JSON using `--json` for integration into other tools.

### `refresh` subcommand

This subcommand refreshes any cached data manually:

```bash
$ swift package-collection refresh
Refreshed 5 configured package collections.
```

SwiftPM will also automatically refresh data under various conditions, but some queries such as search will rely on locally cached data.

### `remove` subcommand

This subcommand removes a collection from the user's list of configured collections:

```bash
$ swift package-collection remove https://www.example.com/packages.json
Removed "Sample Package Collection" from your package collections.
```

### `search` subcommand

This subcommand searches for packages by keywords or module names within imported collections. The result can optionally be returned as JSON using `--json` for
integration into other tools.

#### String-based search

The search command does a string-based search when using the `--keywords` option and returns the list of packages that matches the query:

```bash
$ swift package-collection search [--json] --keywords yaml
https://github.com/jpsim/yams: A sweet and swifty YAML parser built on LibYAML.
...
```

#### Module-based search

The search command does a search for a specific module name when using the `--module` option:

```bash
$ swift package-collection search [--json] --module yams
Package Name: Yams
Latest Version: 4.0.0
Description: A sweet and swifty YAML parser built on LibYAML.
--------------------------------------------------------------
...
```

## Configuration file

Configuration that pertains to package collections are stored in the file `~/.swiftpm/config/collections.json`. It keeps track of user's list of configured collections
and preferences such as those set by the `--trust-unsigned` and `--skip-signature-check` flags in the [`package-collection add` command](#add-subcommand). 

This file is managed through SwiftPM commands and users are not expected to edit it by hand.

---

## Publishing package collections

Package collections can be created and published by anyone. The [swift-package-collection-generator](https://github.com/apple/swift-package-collection-generator) project provides tooling 
intended for package collection publishers:
- [`package-collection-generate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionGenerator): Generate a package collection given a list of package URLs
- [`package-collection-sign`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionSigner): Sign a package collection
- [`package-collection-validate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionValidator): Perform basic validations on a package collection
- [`package-collection-diff`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionDiff): Compare two package collections to see if their contents are different 

### Creating package collections

All package collections must adhere to the [collection data format](../Sources/PackageCollectionsModel/Formats/v1.md) for SwiftPM to be able to consume them. The recommended way
to create package collections is to use [`package-collection-generate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionGenerator). For custom implementations, the data models are available through the [`PackageCollectionsModel` module](../Sources/PackageCollectionsModel).

### Package collection signing (optional)

Package collections can be signed to establish authenticity and protect their integrity. Doing this is optional. Users will be prompted for confirmation before they can add an [unsigned collection](#unsigned-package-collections).

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
the [certificate-pinning configuration](#protecting-package-collections), otherwise the [signature check](#signed-package-collections) will fail. Collection publishers should make the DER-encoded 
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
