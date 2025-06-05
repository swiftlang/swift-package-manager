# Package Collections

@Metadata {
    @Available("Swift", introduced: "5.5")
}

Learn to create, publish and use Swift package collections.

## Overview

Package collections, introduced by [SE-0291](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0291-package-collections.md), are
curated lists of packages and associated metadata that can be imported
by SwiftPM to make discovery of existing packages easier. 
They are authored as static JSON documents 
and can be published to the web or distributed to local file systems. 

Educators and community influencers can publish
package collections to go along with course materials or blog posts, removing the friction of using
packages for the first time and the cognitive overload of deciding which packages are useful for
a particular task. 
Enterprises may use collections to narrow the decision space for their internal
engineering teams, focusing them on a trusted set of vetted packages.

### Using the package-collection CLI

With the `swift package-collection` command-line interface, SwiftPM users can subscribe to package collections. 
Contents of imported package 
collections are accessible to any clients of [libSwiftPM](<doc:SwiftPMAsALibrary>).

`swift package-collection` has the following subcommands:
- [`add`](<doc:PackageCollectionAdd>): Add a new collection
- [`describe`](<doc:PackageCollectionDescribe>): Get metadata for a collection or a package included in an imported collection
- [`list`](<doc:PackageCollectionList>): List configured collections
- [`refresh`](<doc:PackageCollectionRefresh>): Refresh configured collections
- [`remove`](<doc:PackageCollectionRemove>): Remove a configured collection
- [`search`](<doc:PackageCollectionSearch>): Search for packages by keywords or module names within imported collections

### Creating Package Collections

A package collection is a JSON document that contains a list of packages and metadata per package.

Package collections can be created and published by anyone. The [swift-package-collection-generator](https://github.com/apple/swift-package-collection-generator) project provides tooling 
intended for package collection publishers:
- [`package-collection-generate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionGenerator): Generate a package collection given a list of package URLs
- [`package-collection-sign`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionSigner): Sign a package collection
- [`package-collection-validate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionValidator): Perform basic validations on a package collection
- [`package-collection-diff`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionDiff): Compare two package collections to see if their contents are different 

All package collections must adhere to the [collection data format](<doc:Input-Format>) for SwiftPM to be able to consume them. The recommended way
to create package collections is to use [`package-collection-generate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionGenerator). For custom implementations, the data models are available through the [`PackageCollectionsModel` module](https://github.com/swiftlang/swift-package-manager/tree/main/Sources/PackageCollectionsModel).

#### Input Format

To begin, define the top-level metadata about the collection:

* `name`: The name of the package collection, for display purposes only.
* `overview`: A description of the package collection. **Optional.**
* `keywords`: An array of keywords that the collection is associated with. **Optional.**
* `formatVersion`: The version of the format to which the collection conforms. Currently, `1.0` is the only allowed value.
* `revision`: The revision number of this package collection. **Optional.**
* `generatedAt`: The ISO 8601-formatted datetime string when the package collection was generated.
* `generatedBy`: The author of this package collection. **Optional.**
    * `name`: The author name.
* `packages`: A non-empty array of package objects.

### Add packages to the collection

Each item in the `packages` array is a package object with the following properties:

* `url`: The URL of the package. Currently only Git repository URLs are supported. URL should be HTTPS and may contain `.git` suffix.
* `identity`: The [identity](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#36-package-identification) <!-- TODO bp: to replace this link once PackageRegsitry/ is ported. --> of the package if published to registry. **Optional.**
* `summary`: A description of the package. **Optional.**
* `keywords`: An array of keywords that the package is associated with. **Optional.**
* `readmeURL`: The URL of the package's README. **Optional.**
* `license`: The package's *current* license information. **Optional.**
    * `url`: The URL of the license file.
    * `name`: License name. [SPDX identifier](https://spdx.org/licenses/) (e.g., `Apache-2.0`, `MIT`, etc.) preferred. Omit if unknown. **Optional.**
* `versions`: An array of version objects representing the most recent and/or relevant releases of the package.

When a package is [added to a collection](<doc:PackageCollectionAdd>), the package object will appear in the collection's `packages` array with the properties described above.

### Add versions to a package

A version object has metadata extracted from `Package.swift` and optionally additional metadata from other sources:

* `version`: The semantic version string.
* `summary`: A description of the package version. **Optional.**
* `manifests`: A non-empty map of manifests by Swift tools version. The keys are (semantic) tools version (more on this below), while the values are:
    * `toolsVersion`: The Swift tools version specified in the manifest.
    * `packageName`: The name of the package.
    * `targets`: An array of the package version's targets.
        * `name`: The target name.
        * `moduleName`: The module name if this target can be imported as a module. **Optional.**
    * `products`: An array of the package version's products.
        * `name`: The product name.
        * `type`: The product type. This must have the same JSON representation as SwiftPM's `PackageModel.ProductType`.
        * `target`: An array of the product’s targets.
    * `minimumPlatformVersions`: An array of the package version’s supported platforms specified in `Package.swift`. **Optional.** 

```json
{
  "5.2": {
    "toolsVersion": "5.2",
    "packageName": "MyPackage",
    "targets": [
      {
        "name": "MyTarget",
        "moduleName": "MyTarget"
      }
    ],
    "products": [
      {
        "name": "MyProduct",
        "type": {
          "library": ["automatic"]
        },
        "targets": ["MyTarget"]
      }
    ],
    "minimumPlatformVersions": [
      {
        "name": "macOS",
        "version": "10.15"
      }
    ]
  }
}
```

* `defaultToolsVersion`: The Swift tools version of the default manifest. The `manifests` map must contain this in its keys. 
* `verifiedCompatibility`: An array of compatible platforms and Swift versions that has been tested and verified for. Valid platform names include `macOS`, `iOS`, `tvOS`, `watchOS`, `Linux`, `Android`, and `Windows`. Swift version should be semantic version string and as specific as possible. **Optional.**

```json
{
  "platform": {
    "name": "macOS"
  },
  "swiftVersion": "5.3.2"
}
```

* `license`: The package version's license. **Optional.**
    * `url`: The URL of the license file.
    * `name`: License name. [SPDX identifier](https://spdx.org/licenses/) (e.g., `Apache-2.0`, `MIT`, etc.) preferred. Omit if unknown. **Optional.**
* `author`: The package version's author. **Optional.**
    * `name`: The author of the package version.
* `signer`: The signer of the package version. **Optional.** Refer to [documentation](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md#package-signing) <!-- TODO bp: to replace this link once PackageRegistry/ is ported. --> on package signing for details.
    * `type`: The signer type. Currently the only valid value is `ADP` (Apple Developer Program).
    * `commonName`: The common name of the signing certificate's subject.
    * `organizationalUnitName`: The organizational unit name of the signing certificate's subject.
    * `organizationName`: The organization name of the signing certificate's subject.           
* `createdAt`: The ISO 8601-formatted datetime string when the package version was created. **Optional.**

### Version-specific manifests

Package collection generators should include data from the "default" manifest `Package.swift` as well as [version-specific manifest(s)](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/Usage.md#version-specific-manifest-selection) <!-- TODO bp: to replace this link once Usage.md is ported. -->.

The keys of the `manifests` map are Swift tools (semantic) versions:
* For `Package.swift`, the tools version specified in `Package.swift` should be used.
* For version-specific manifests, the tools version specified in the filename should be used. For example, for `Package@swift-4.2.swift` it would be `4.2`. The tools version in the manifest must match that in the filename. 

### Version-specific tags

 [Version-specific tags](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/Usage.md#version-specific-tag-selection) <!-- TODO bp: to replace this link once Usage.md is ported. --> are not
 supported by package collections.

### Configuration File

Configuration that pertains to package collections are stored in the file `~/.swiftpm/config/collections.json`. 
It keeps track of user's list of configured collections
and preferences such as those set by the `--trust-unsigned` and `--skip-signature-check` flags in the [`package-collection add` command](<doc:PackageCollectionAdd>). 

> Note: This file is managed through SwiftPM commands and users are not expected to edit it by hand.

## Example

```json
{
  "name": "Sample Package Collection",
  "overview": "This is a sample package collection listing made-up packages.",
  "keywords": ["sample package collection"],
  "formatVersion": "1.0",
  "revision": 3,
  "generatedAt": "2020-10-22T06:03:52Z",
  "packages": [
    {
      "url": "https://www.example.com/repos/RepoOne.git",
      "summary": "Package One",
      "readmeURL": "https://www.example.com/repos/RepoOne/README",
      "license": {
        "name": "Apache-2.0",
        "url": "https://www.example.com/repos/RepoOne/LICENSE"
      },
      "versions": [
        {
          "version": "0.1.0",
          "summary": "Fixed a few bugs",
          "manifests": {
            "5.1": {
              "toolsVersion": "5.1",
              "packageName": "PackageOne",
              "targets": [
                {
                  "name": "Foo",
                  "moduleName": "Foo"
                }
              ],
              "products": [
                {
                  "name": "Foo",
                  "type": {
                    "library": ["automatic"]
                  },
                  "targets": ["Foo"]
                }
              ]
            }
          },
          "defaultToolsVersion": "5.1",
          "verifiedCompatibility": [
            {
              "platform": { "name": "macOS" },
              "swiftVersion": "5.1"
            },
            {
              "platform": { "name": "iOS" },
              "swiftVersion": "5.1"
            },
            {
              "platform": { "name": "Linux" },
              "swiftVersion": "5.1"
            }
          ],
          "license": {
            "name": "Apache-2.0",
            "url": "https://www.example.com/repos/RepoOne/LICENSE"
          },
          "createdAt": "2020-10-21T09:25:36Z"
        }
      ]
    },
    {
      "url": "https://www.example.com/repos/RepoTwo.git",
      "summary": "Package Two",
      "readmeURL": "https://www.example.com/repos/RepoTwo/README",
      "versions": [
        {
          "version": "2.1.0",
          "manifests": {
            "5.2": {
              "toolsVersion": "5.2",
              "packageName": "PackageTwo",
              "targets": [
                {
                  "name": "Bar",
                  "moduleName": "Bar"
                }
              ],
              "products": [
                {
                  "name": "Bar",
                  "type": {
                    "library": ["automatic"]
                  },
                  "targets": ["Bar"]
                }
              ]
            }
          },
          "defaultToolsVersion": "5.2"
        },
        {
          "version": "1.8.3",
          "manifests": {
            "5.0": {
              "toolsVersion": "5.0",
              "packageName": "PackageTwo",
              "targets": [
                {
                  "name": "Bar",
                  "moduleName": "Bar"
                }
              ],
              "products": [
                {
                  "name": "Bar",
                  "type": {
                    "library": ["automatic"]
                  },
                  "targets": ["Bar"]
                }
              ]
            }
          },
          "defaultToolsVersion": "5.0"
        }
      ]
    }
  ]
}
```


## Signing and protecting package collections

Package collections can be signed to establish authenticity and protect their integrity. 
Doing this is optional. 
Users will be prompted for confirmation before they can add an [unsigned collection](<doc:PackageCollectionAdd#Unsigned-package-collections>).

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

- The signature string (represented by `"<SIGNATURE>"`) is used to verify the contents of the collection file haven't been tampered with since it was signed when SwiftPM user [adds the collection](<doc:PackageCollectionAdd#Signed-package-collections>) to their configured list of collections. It includes the certificate's public key and chain.
- `certificate` contains details extracted from the signing certificate. `subject.commonName` should be consistent with the name of the publisher so that it's recognizable by users. The root of the certificate must be [installed and trusted on users' machines](<doc:PackageCollectionAdd#Trusted-root-certificates>).

### Requirements on signing certificate

Certificates used for signing package collections must meet the following requirements, which are checked and enforced during signature generation (publishers) and verification (SwiftPM users):
- The timestamp at which signing/verification is done must fall within the signing certificate's validity period.
- The certificate's "Extended Key Usage" extension must include "Code Signing".
- The certificate must use either 256-bit EC (recommended for enhanced security) or 2048-bit RSA key.
- The certificate must not be revoked. The certificate authority must support OCSP, which means the certificate must have the "Certificate Authority Information Access" extension that includes OCSP as a method, specifying the responder's URL.
- The certificate chain is valid and root certificate must be trusted.

Non-expired, non-revoked Swift Package Collection certificates from [developer.apple.com](https://developer.apple.com) satisfy all of the criteria above.

#### Trusted root certificates

With the `package-collection-sign` tool, the root certificate provided as input for signing a collection is automatically trusted. When SwiftPM user tries to add the collection, however,
the root certificate must either be preinstalled with the OS (Apple platforms only) or found in the `~/.swiftpm/config/trust-root-certs` directory (all platforms) or shipped with 
the [certificate-pinning configuration](<doc:#Protecting-package-collections>), otherwise the [signature check](<doc:PackageCollectionAdd#Signed-package-collections>) will fail.
Collection publishers should make the DER-encoded 
root certificate(s) that they use downloadable so that users can adjust their setup if needed.


## Protecting package collections

[Signing](<doc:PackageCollectionAdd#Unsigned-package-collections>) can provide some degree of protection on package collections and reduce the risks of their contents being modified by malicious actors, but it doesn't
prevent the following attack vectors:
- **Signature stripping**: This involves attackers removing signature from a signed collection, causing it to be downloaded as an [unsigned collection](<doc:PackageCollectionAdd#Unsigned-package-collections>) and bypassing signature check. In this case, publishers should make it known that the collection is signed, and SwiftPM users should abort the `add` operation when the "unsigned" warning appears on a supposedly signed collection.
- **Signature replacement**: Attackers may modify a collection then re-sign it using a different certificate, either pretend to be the same entity or as some other entity, and SwiftPM will accept it as long as the [signature is valid](<doc:PackageCollectionAdd#Signed-package-collections>).

To defend against these attacks, SwiftPM has certificate-pinning configuration that allows collection publishers to:
- Require signature check on their collections — this defends against "signature stripping".
- Restrict what certificate can be used for signing — this defends against "signature replacement".

The process for collection publishers to define their certificate-pinning configuration is as follows:
1. Edit [`PackageCollectionSourceCertificatePolicy`](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageCollections/PackageCollections%2BCertificatePolicy.swift) and add an entry to the `defaultSourceCertPolicies` dictionary:

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

