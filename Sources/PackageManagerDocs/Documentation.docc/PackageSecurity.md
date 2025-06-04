# Package Security

Learn about the security features that the package manager implements.

## Trust on First Use

The package manager records **fingerprints** of downloaded package versions so that
it can perform [trust-on-first-use](https://en.wikipedia.org/wiki/Trust_on_first_use)
(TOFU). 
That is, when a package version is downloaded for the first time, the package manager trusts that 
it has downloaded the correct contents and requires subsequent downloads of the same 
package version to have the same fingerprint. 
If the fingerprint changes, it might be an indicator that the package has been
compromised and the package manager either warns or returns an error.

Depending on where a package version is downloaded from, a different value is
used as its fingerprint:
                             
| Package Version Origin | Fingerprint |
| ---------------------- | ----------- |
| Git repository         | Git hash of the revision |
| Package registry       | Checksum of the source archive |

The package manager keeps version fingerprints for each package in a single file
under the `~/.swiftpm/security/fingerprints` directory.
  - For a Git repository package, the fingerprint filename takes the form of `{PACKAGE_NAME}-{REPOSITORY_URL_HASH}.json` (such as `LinkedList-5ddbcf15.json`).
  - For a registry package, the fingerprint filename takes the form of `{PACKAGE_ID}.json` (such as `mona.LinkedList.json`).

For packages retrieved from a registry, the package manager expects all registries to provide consistent fingerprints for packages they host.
If the archive is downloaded for the first time, Package manager [fetches metadata of the package release](<doc:RegistryServerSpecification#4.2.-Fetch-information-about-a-package-release>) to obtain the expected checksum.
Otherwise, Package manager compares the checksum with that in local storage (`~/.swiftpm/security/fingerprints/`) saved from previous download.


If registries have conflicting fingerprints, Package manager reports that as an error.
This can be tuned down to a warning by setting the [build](<doc:SwiftBuild>) option `--resolver-fingerprint-checking` to `warn` (default is `strict`).

### Signed packages

<!-- TODO bp: merge package signing for registry + collection -->

To sign a package release, package author will need to set either the `signing-identity` (for reading from operating system's identity store such as Keychain in macOS), or `private-key-path` and `cert-chain-paths` (for reading from files) options of the `publish` subcommand such that Package manager can locate the signing key and certificate.

If the certificate chain's root and intermediates are known by Package manager, then package author would only need to provide the leaf signing certificate in `cert-chain-paths`. 

Otherwise, the entire certificate chain should be provided as `cert-chain-paths` so that all of the certificates will be included in the signature and make it possible for Package manager to reconstruct the certificate chain for validation later. 
This is applicable to `signing-identity` as well (i.e., `signing-identity` can be used in combination with `cert-chain-paths` to provide the entire certificate chain).

If the root of the signing certificate is not in Package manager's default trust store, package author is responsible for telling package users to include the root certificate in their local [trust roots](<doc:Trusted-vs-untrusted-certificate>) directory, or else [signature validation](<doc:Validating-signed-packages>) may fail upon download because the signing certificate is not trusted.

#### Registry

A registry may support or require signing.
[SE-0391](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-signing) adds package signing support to Swift Package Manager.
Package manager determines if a downloaded archive is signed by checking for presence of the `X-Swift-Package-Signature-Format` and `X-Swift-Package-Signature` headers in the HTTP response.

#### Package Collections

Package collection publishers may [sign a collection to protect its contents](<doc:PackageCollections#Signing-and-protecting-package-collections>) from being tampered with. 
If a collection is signed, Package manager will check that the signature is valid before importing it and return an error if any of these fails:
- The file's contents, signature excluded, must match what was used to generate the signature. 
In other words, this checks to see if the collection has been altered since it was signed.
- The signing certificate must meet all the [requirements](<doc:PackageCollections#Requirements-on-signing-certificate>).

For more information on adding package collections, see <doc:PackageCollectionAdd#Signed-package-collections>.

### Validating signed packages 

Once Package manager determines that a download archive is signed, it then performs a series of validations based on a user's
[security configuration](<doc:UsingSwiftPackageRegistry#Security-configuration>).
- If the archive is unsigned, Package manager will error/prompt/warn/allow based on the `signing.onUnsigned` configuration. 
- If the archive is signed, Package manager will validate the signature and the signing certificate chain. (see the following sections for details)

##### Trusted vs. untrusted certificate

A certificate is trusted if it is chained to any root in Swift Package Manager's trust store, which consists of:
- Swift Package Manager's default trust store, if `signing.includeDefaultTrustedRootCertificates` is `true`.
- Custom root(s) in the configured trusted roots directory at `signing.trustedRootCertificatesPath`. Certificates must be DER-encoded.

Otherwise, a certificate is untrusted and handled according to the `signing.onUntrustedCertificate` configuration. 
If user opts to continue with the untrusted certificate, Package manager will proceed with the archive as if it were an unsigned package.

###### Trusted root certificates for Package Collections



##### Certificate policies

Swift Package Manager requires all certificates used for package signing to have the "code signing" extended key usage extension. They must also satisfy the core policies from [RFC 5280](https://www.rfc-editor.org/rfc/rfc5280), as implemented by [swift-certificates](https://github.com/apple/swift-certificates). 

Users can configure certificate expiry and revocation check through the `signing.validationChecks.certificateExpiration` and `signing.validationChecks.certificateRevocation` configuration, respectively. Note that revocation check implicitly requires expiry check.
   
An invalid signing certificate would result in Package manager rejecting the archive.

### Publisher TOFU

Some certificates allow Package manager to extract additional information about the signing identity. For packages signed with these certificates, Package manager will perform publisher TOFU to ensure the signer remains the same across all versions of the package. 

The `--resolver-signing-entity-checking` option controls whether publisher mismatch should result in a warning (`warn`) or error (`strict`). Data used by publisher TOFU is saved to `~/.swiftpm/security/signing-entities/`.
