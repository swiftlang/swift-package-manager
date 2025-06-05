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

### Package signing

#### Packages from a registry

A registry may support or require signing.
To sign a package release, package authors will need to set either the `signing-identity` (for reading from operating system's identity store such as Keychain in macOS), or `private-key-path` and `cert-chain-paths` (for reading from files) options of the [`swift package-registry publish`](<doc:PackageRegistryPublish>) subcommand such that Package manager can locate the signing key and certificate.

If the certificate chain's root and intermediates are known by Package manager, then package author would only need to provide the leaf signing certificate in `cert-chain-paths`. 

Otherwise, the entire certificate chain should be provided as `cert-chain-paths` so that all of the certificates will be included in the signature and make it possible for Package manager to reconstruct the certificate chain for validation later. 
This is applicable to `signing-identity` as well (i.e., `signing-identity` can be used in combination with `cert-chain-paths` to provide the entire certificate chain).

If the root of the signing certificate is not in Package manager's default trust store, package author is responsible for telling package users to include the root certificate in their local [trust roots](<doc:PackageSecurity#Trusted-vs.-untrusted-certificate>) directory, or else [signature validation](<doc:Validating-signed-packages>) may fail upon download because the signing certificate is not trusted.


For more information on signed registry packages, see <doc:UsingSwiftPackageRegistry#Publisher-TOFU>.

#### Signed package collections

Package collection publishers may [sign a collection to protect its contents](<doc:PackageCollections#Signing-and-protecting-package-collections>) from being tampered with. 
If a collection is signed, Package manager will check that the signature is valid before importing it and return an error if any of these fails:
- The file's contents, signature excluded, must match what was used to generate the signature. 
In other words, this checks to see if the collection has been altered since it was signed.
- The signing certificate must meet all the [requirements](<doc:#Requirements-on-signing-certificate>).

Users will be prompted for confirmation before they can add an [unsigned collection](<doc:PackageCollectionAdd#Unsigned-package-collections>).

 [`package-collection-sign`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionSigner) helps publishers sign their package collections. 
 To generate a signature one must provide:
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

 - The signature string (represented by `"<SIGNATURE>"`) is used to verify the contents of the collection file haven't been tampered with since it was signed when a Package manager user [adds the collection](<doc:PackageCollectionAdd>) to their configured list of collections. It includes the certificate's public key and chain.
 - `certificate` contains details extracted from the signing certificate. `subject.commonName` should be consistent with the name of the publisher so that it's recognizable by users. The root of the certificate must be [installed and trusted on users' machines](<doc:PackageCollectionAdd#trusted-root-certificates>).

For more information on adding package collections, see <doc:PackageCollectionAdd#Signed-package-collections>. 

###### Requirements on signing certificate

Certificates used for signing package collections must meet the following requirements, which are checked and enforced during signature generation (publishers) and verification (Swift Package Manager users):
- The timestamp at which signing/verification is done must fall within the signing certificate's validity period.
- The certificate's "Extended Key Usage" extension must include "Code Signing".
- The certificate must use either 256-bit EC (recommended for enhanced security) or 2048-bit RSA key.
- The certificate must not be revoked. The certificate authority must support OCSP, which means the certificate must have the "Certificate Authority Information Access" extension that includes OCSP as a method, specifying the responder's URL.
- The certificate chain is valid and root certificate must be trusted.

Non-expired, non-revoked Swift Package Collection certificates from [developer.apple.com](https://developer.apple.com) satisfy all of the criteria above.

<!--To sign a package release, package authors will need to set either the `signing-identity` (for reading from operating system's identity store such as Keychain in macOS), or `private-key-path` and `cert-chain-paths` (for reading from files) options of the `publish` subcommand such that Package manager can locate the signing key and certificate.-->
<!---->
<!--If the certificate chain's root and intermediates are known by Package manager, then package author would only need to provide the leaf signing certificate in `cert-chain-paths`. -->
<!---->
<!--Otherwise, the entire certificate chain should be provided as `cert-chain-paths` so that all of the certificates will be included in the signature and make it possible for Package manager to reconstruct the certificate chain for validation later. -->
<!--This is applicable to `signing-identity` as well (i.e., `signing-identity` can be used in combination with `cert-chain-paths` to provide the entire certificate chain).-->
<!---->
<!--If the root of the signing certificate is not in Package manager's default trust store, package author is responsible for telling package users to include the root certificate in their local [trust roots](<doc:Trusted-vs-untrusted-certificate>) directory, or else [signature validation](<doc:Validating-signed-packages>) may fail upon download because the signing certificate is not trusted.-->

<!--#### Registry-->
<!---->
<!--[SE-0391](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-signing) adds package signing support to Swift Package Manager.-->
<!--A registry may support or require signing.-->
<!--Package manager determines if a downloaded archive is signed by checking for presence of the `X-Swift-Package-Signature-Format` and `X-Swift-Package-Signature` headers in the HTTP response.-->
<!---->
<!--For more information on package signing for Registry, see <doc:UsingSwiftPackageRegistry#Package-signing>.-->
<!---->
<!--#### Package Collections-->
<!---->
<!--Package collection publishers may [sign a collection to protect its contents](<doc:PackageCollections#Signing-and-protecting-package-collections>) from being tampered with. -->
<!--If a collection is signed, Package manager will check that the signature is valid before importing it and return an error if any of these fails:-->
<!--- The file's contents, signature excluded, must match what was used to generate the signature. -->
<!--In other words, this checks to see if the collection has been altered since it was signed.-->
<!--- The signing certificate must meet all the [requirements](<doc:PackageCollections#Requirements-on-signing-certificate>).-->
<!---->
<!--For more information on adding signed package collections, see <doc:PackageCollectionAdd#Signed-package-collections>.-->

<!--### Validating signed packages -->
<!-- TODO bp: this seems speicific to registry -->
<!--Once Package manager determines that a download archive is signed, it then performs a series of validations based on a user's-->
<!--[security configuration](<doc:UsingSwiftPackageRegistry#Security-configuration>).-->
<!--- If the archive is unsigned, Package manager will error/prompt/warn/allow based on the `signing.onUnsigned` configuration. -->
<!--- If the archive is signed, Package manager will validate the signature and the signing certificate chain. (see the following sections for details)-->

##### Trusted vs. untrusted certificate

A certificate is trusted if it is chained to any root in Swift Package Manager's trust store, which consists of:
- Swift Package Manager's default trust store, if `signing.includeDefaultTrustedRootCertificates` is `true`.
- Custom root(s) in the configured trusted roots directory at `signing.trustedRootCertificatesPath`. Certificates must be DER-encoded.

Otherwise, a certificate is untrusted and handled according to the `signing.onUntrustedCertificate` configuration. 
If a user opts to continue with the untrusted certificate, Package manager will proceed as if it were an unsigned package.

###### Trusted root certificates and validating signed packages <!-- for package collections -->

Since generating a collection <!-- TODO bp: remove collection? does this apply to registry too?--> signature requires a certificate, part of the signature check involves validating the certificate and its chain and making sure that the root certificate is trusted.
On Apple platforms, all root certificates that come preinstalled with the OS are automatically trusted.
Users may include additional certificates to trust by placing them in the `~/.swiftpm/config/trust-root-certs` directory. 
On non-Apple platforms, there are no trusted root certificates by default other than those shipped with the [certificate-pinning configuration](<doc:PackageCollections#Protecting-package-collections>).
Only those found in `~/.swiftpm/config/trust-root-certs` are trusted. This means that the signature check will always fail unless the `trust-root-certs` directory is set up.
Users can explicitly specify they trust a publisher and any collections they publish, by obtaining that publisher's root certificate and saving it to `~/.swiftpm/config/trust-root-certs`.
The root certificates must be DER-encoded.
Since SwiftPM trusts all certificate chains under a root, depending on what roots are installed, some publishers may already be trusted implicitly and users don't need to explicitly specify each one. 


With the `package-collection-sign` tool, the root certificate provided as input for signing a collection is automatically trusted. 
When a Package manager user tries to add the collection, however, the root certificate must either be preinstalled with the OS (Apple platforms only) or found in the `~/.swiftpm/config/trust-root-certs` directory (all platforms) or shipped with the [certificate-pinning configuration](<doc:PackageCollections#Protecting-package-collections>), otherwise the [signature check](<doc:PackageCollectionAdd#Signed-package-collections>) will fail. Collection publishers should make the DER-encoded root certificate(s) that they use downloadable so that users can adjust their setup if needed.

##### Certificate policies

Swift Package Manager requires all certificates used for package signing to have the "code signing" extended key usage extension. They must also satisfy the core policies from [RFC 5280](https://www.rfc-editor.org/rfc/rfc5280), as implemented by [swift-certificates](https://github.com/apple/swift-certificates). 

Users can configure certificate expiry and revocation check through the `signing.validationChecks.certificateExpiration` and `signing.validationChecks.certificateRevocation` configuration, respectively. Note that revocation check implicitly requires expiry check.
   
An invalid signing certificate would result in Package manager rejecting the archive when downloading from a registry, or the package collection.

<!--### Publisher TOFU-->
<!---->
<!--Some certificates allow Package manager to extract additional information about the signing identity. For packages signed with these certificates, Package manager will perform publisher TOFU to ensure the signer remains the same across all versions of the package. -->
<!---->
<!--The `--resolver-signing-entity-checking` option controls whether publisher mismatch should result in a warning (`warn`) or error (`strict`). Data used by publisher TOFU is saved to `~/.swiftpm/security/signing-entities/`.-->

### Signature formats
