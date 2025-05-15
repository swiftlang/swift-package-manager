# swift package-collection add

@Metadata {
    @PageImage(purpose: icon, source: command-icon)
}

## Overview

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

## Usage

Add a new collection.

```
package-collection add <collection-url> [--order=<order>] [--trust-unsigned] [--skip-signature-check] [--package-path=<package-path>] [--cache-path=<cache-path>] [--config-path=<config-path>] [--security-path=<security-path>] [--scratch-path=<scratch-path>]     [--swift-sdks-path=<swift-sdks-path>] [--toolset=<toolset>...] [--pkg-config-path=<pkg-config-path>...]   [--enable-dependency-cache|disable-dependency-cache]  [--enable-build-manifest-caching|disable-build-manifest-caching] [--manifest-cache=<manifest-cache>] [--enable-experimental-prebuilts|disable-experimental-prebuilts] [--verbose] [--very-verbose|vv] [--quiet] [--color-diagnostics|no-color-diagnostics] [--disable-sandbox] [--netrc] [--enable-netrc|disable-netrc] [--netrc-file=<netrc-file>] [--enable-keychain|disable-keychain] [--resolver-fingerprint-checking=<resolver-fingerprint-checking>] [--resolver-signing-entity-checking=<resolver-signing-entity-checking>] [--enable-signature-validation|disable-signature-validation] [--enable-prefetching|disable-prefetching] [--force-resolved-versions|disable-automatic-resolution|only-use-versions-from-resolved-file] [--skip-update] [--disable-scm-to-registry-transformation] [--use-registry-identity-for-scm] [--replace-scm-with-registry]  [--default-registry-url=<default-registry-url>] [--configuration=<configuration>] [--=<Xcc>...] [--=<Xswiftc>...] [--=<Xlinker>...] [--=<Xcxx>...]    [--triple=<triple>] [--sdk=<sdk>] [--toolchain=<toolchain>]   [--swift-sdk=<swift-sdk>] [--sanitize=<sanitize>...] [--auto-index-store|enable-index-store|disable-index-store]   [--enable-parseable-module-interfaces] [--jobs=<jobs>] [--use-integrated-swift-driver] [--explicit-target-dependency-import-check=<explicit-target-dependency-import-check>] [--experimental-explicit-module-build] [--build-system=<build-system>] [--=<debug-info-format>]      [--enable-dead-strip|disable-dead-strip] [--disable-local-rpath] [--version] [--help]
```

<!--### Signed package collections-->
<!---->
<!--Package collection publishers may sign a collection to protect its contents from being tampered with. If a collection is signed, SwiftPM will check that the -->
<!--signature is valid before importing it and return an error if any of these fails:-->
<!--- The file's contents, signature excluded, must match what was used to generate the signature. In other words, this checks to see if the collection has been altered since it was signed.-->
<!--- The signing certificate must meet all the [requirements](#requirements-on-signing-certificate).-->
<!---->
<!--```bash-->
<!--$ swift package-collection add https://www.example.com/bad-packages.json-->
<!--The collection's signature is invalid. If you would like to continue please rerun command with '--skip-signature-check'.-->
<!--```-->
<!---->
<!--Users may continue adding the collection despite the error or preemptively skip the signature check on a package collection by passing the `--skip-signature-check` flag:-->
<!---->
<!--```bash-->
<!--$ swift package-collection add https://www.example.com/packages.json --skip-signature-check-->
<!--```-->
<!---->
<!--For package collections hosted on the web, publishers may ask SwiftPM to [enforce the signature requirement](#protecting-package-collections). If a package collection is-->
<!--expected to be signed but it isn't, user will see the following error message:-->
<!---->
<!--```bash-->
<!--$ swift package-collection add https://www.example.com/bad-packages.json-->
<!--The collection is missing required signature, which means it might have been compromised.-->
<!--```-->
<!---->
<!--Users should NOT add the package collection in this case.-->
<!---->
<!--#### Trusted root certificates-->
<!---->
<!--Since generating a collection signature requires a certificate, part of the signature check involves validating the certificate and its chain and making sure that the root certificate is trusted.-->
<!---->
<!--On Apple platforms, all root certificates that come preinstalled with the OS are automatically trusted. Users may include additional certificates to trust by placing -->
<!--them in the `~/.swiftpm/config/trust-root-certs` directory. -->
<!---->
<!--On non-Apple platforms, there are no trusted root certificates by default other than those shipped with the [certificate-pinning configuration](#protecting-package-collections). Only those -->
<!--found in `~/.swiftpm/config/trust-root-certs` are trusted. This means that the signature check will always fail unless the `trust-root-certs` directory is set up:-->
<!---->
<!--```bash-->
<!--$ swift package-collection add https://www.example.com/packages.json-->
<!--The collection's signature cannot be verified due to missing configuration.-->
<!--```-->
<!---->
<!--Users can explicitly specify they trust a publisher and any collections they publish, by obtaining that publisher's root certificate and saving it to `~/.swiftpm/config/trust-root-certs`. The -->
<!--root certificates must be DER-encoded. Since SwiftPM trusts all certificate chains under a root, depending on what roots are installed, some publishers may already be trusted implicitly and -->
<!--users don't need to explicitly specify each one. -->
<!---->
<!--#### Requirements on signing certificate-->
<!---->
<!--Certificates used for signing package collections must meet the following requirements, which are checked and enforced during signature generation (publishers) and verification (SwiftPM users):-->
<!--- The timestamp at which signing/verification is done must fall within the signing certificate's validity period.-->
<!--- The certificate's "Extended Key Usage" extension must include "Code Signing".-->
<!--- The certificate must use either 256-bit EC (recommended for enhanced security) or 2048-bit RSA key.-->
<!--- The certificate must not be revoked. The certificate authority must support OCSP, which means the certificate must have the "Certificate Authority Information Access" extension that includes OCSP as a method, specifying the responder's URL.-->
<!--- The certificate chain is valid and root certificate must be trusted.-->
<!---->
<!--Non-expired, non-revoked Swift Package Collection certificates from [developer.apple.com](https://developer.apple.com) satisfy all of the criteria above.-->
<!---->
<!--### Protecting package collections-->
<!---->
<!--[Signing](#package-collection-signing-optional) can provide some degree of protection on package collections and reduce the risks of their contents being modified by malicious actors, but it doesn't-->
<!--prevent the following attack vectors:-->
<!--- **Signature stripping**: This involves attackers removing signature from a signed collection, causing it to be downloaded as an [unsigned collection](#unsigned-package-collections) and bypassing signature check. In this case, publishers should make it known that the collection is signed, and SwiftPM users should abort the `add` operation when the "unsigned" warning appears on a supposedly signed collection.-->
<!--- **Signature replacement**: Attackers may modify a collection then re-sign it using a different certificate, either pretend to be the same entity or as some other entity, and SwiftPM will accept it as long as the [signature is valid](#signed-package-collections).-->
<!---->
<!--To defend against these attacks, SwiftPM has certificate-pinning configuration that allows collection publishers to:-->
<!--- Require signature check on their collections — this defends against "signature stripping".-->
<!--- Restrict what certificate can be used for signing — this defends against "signature replacement".-->
<!---->
<!--The process for collection publishers to define their certificate-pinning configuration is as follows:-->
<!--1. Edit [`PackageCollectionSourceCertificatePolicy`](../Sources/PackageCollections/PackageCollections+CertificatePolicy.swift) and add an entry to the `defaultSourceCertPolicies` dictionary:-->
<!---->
<!--```swift-->
<!--private static let defaultSourceCertPolicies: [String: CertificatePolicyConfig] = [-->
<!--    // The key should be the "host" component of the package collection URL.-->
<!--    // This would require all package collections hosted on this domain to be signed.-->
<!--    "www.example.com": CertificatePolicyConfig(-->
<!--        // The signing certificate must have this subject user ID-->
<!--        certPolicyKey: CertificatePolicyKey.default(subjectUserID: "exampleUserID"),-->
<!--        /*-->
<!--         To compute base64-encoded string of a certificate:-->
<!--         let certificateURL = URL(fileURLWithPath: <path to DER-encoded root certificate file>)-->
<!--         let certificateData = try Data(contentsOf: certificateURL)-->
<!--         let base64EncoodedCertificate = certificateData.base64EncodedString()-->
<!--         */-->
<!--        base64EncodedRootCerts: ["<base64-encoded root certificate>"]-->
<!--    )-->
<!--]-->
<!--```-->
<!---->
<!--2. Open a pull request for review. The requestor must be able to provide proof of their identity and ownership on the domain:-->
<!--    - The requestor must provide the actual certificate files (DER-encoded). The SwiftPM team will verify that the certificate chain is valid and the values provided in the PR are correct.-->
<!--    - The requestor must add a TXT record referencing the pull request. The SwiftPM team will run `dig -t txt <DOMAIN>` to verify. This would act as proof of domain ownership.-->
<!--3. After the changes are accepted, they will take effect in the next SwiftPM release.-->
<!---->
<!--Since certificate-pinning configuration is associated with web domains, it can only be applied to signed collections hosted on the web (i.e., URL begins with  `https://`) and does -->
<!--not cover those found on local file system (i.e., URL begins with `file://`). -->
<!---->
<!---->
<!--### Unsigned package collections-->
<!---->
<!--Users will get an error when trying to add an unsigned package collection:-->
<!---->
<!--```bash-->
<!--$ swift package-collection add https://www.example.com/packages.json-->
<!--The collection is not signed. If you would still like to add it please rerun 'add' with '--trust-unsigned'.-->
<!--```-->
<!---->
<!--To continue user must confirm their trust by passing the `--trust-unsigned` flag:-->
<!---->
<!--```bash-->
<!--$ swift package-collection add https://www.example.com/packages.json --trust-unsigned-->
<!--```-->
<!---->
<!--The `--skip-signature-check` flag has no effects on unsigned collections.-->

## Command Options

- term **collection-url:**

*URL of the collection to add.*


- term **--order=\<order\>:**

*Sort order for the added collection.*


- term **--trust-unsigned:**

*Trust the collection even if it is unsigned.*


- term **--skip-signature-check:**

*Skip signature check if the collection is signed.*


- term **--package-path=\<package-path\>:**

*Specify the package path to operate on (default current directory). This changes the working directory before any other operation.*


- term **--cache-path=\<cache-path\>:**

*Specify the shared cache directory path.*


- term **--config-path=\<config-path\>:**

*Specify the shared configuration directory path.*


- term **--security-path=\<security-path\>:**

*Specify the shared security directory path.*


- term **--scratch-path=\<scratch-path\>:**

*Specify a custom scratch directory path. (default .build)*


- term **--swift-sdks-path=\<swift-sdks-path\>:**

*Path to the directory containing installed Swift SDKs.*


- term **--toolset=\<toolset\>:**

*Specify a toolset JSON file to use when building for the target platform. Use the option multiple times to specify more than one toolset. Toolsets will be merged in the order they're specified into a single final toolset for the current build.*


- term **--pkg-config-path=\<pkg-config-path\>:**

*Specify alternative path to search for pkg-config `.pc` files. Use the option multiple times to
specify more than one path.*


- term **--enable-dependency-cache|disable-dependency-cache:**

*Use a shared cache when fetching dependencies.*


- term **--enable-build-manifest-caching|disable-build-manifest-caching:**


- term **--manifest-cache=\<manifest-cache\>:**

*Caching mode of Package.swift manifests. Valid values are: (shared: shared cache, local: package's build directory, none: disabled)*


- term **--enable-experimental-prebuilts|disable-experimental-prebuilts:**

*Whether to use prebuilt swift-syntax libraries for macros.*


- term **--verbose:**

*Increase verbosity to include informational output.*


- term **--very-verbose|vv:**

*Increase verbosity to include debug output.*


- term **--quiet:**

*Decrease verbosity to only include error output.*


- term **--color-diagnostics|no-color-diagnostics:**

*Enables or disables color diagnostics when printing to a TTY. 
By default, color diagnostics are enabled when connected to a TTY and disabled otherwise.*


- term **--disable-sandbox:**

*Disable using the sandbox when executing subprocesses.*


- term **--netrc:**

*Use netrc file even in cases where other credential stores are preferred.*


- term **--enable-netrc|disable-netrc:**

*Load credentials from a netrc file.*


- term **--netrc-file=\<netrc-file\>:**

*Specify the netrc file path.*


- term **--enable-keychain|disable-keychain:**

*Search credentials in macOS keychain.*


- term **--resolver-fingerprint-checking=\<resolver-fingerprint-checking\>:**


- term **--resolver-signing-entity-checking=\<resolver-signing-entity-checking\>:**


- term **--enable-signature-validation|disable-signature-validation:**

*Validate signature of a signed package release downloaded from registry.*


- term **--enable-prefetching|disable-prefetching:**


- term **--force-resolved-versions|disable-automatic-resolution|only-use-versions-from-resolved-file:**

*Only use versions from the Package.resolved file and fail resolution if it is out-of-date.*


- term **--skip-update:**

*Skip updating dependencies from their remote during a resolution.*


- term **--disable-scm-to-registry-transformation:**

*Disable source control to registry transformation.*


- term **--use-registry-identity-for-scm:**

*Look up source control dependencies in the registry and use their registry identity when possible to help deduplicate across the two origins.*


- term **--replace-scm-with-registry:**

*Look up source control dependencies in the registry and use the registry to retrieve them instead of source control when possible.*


- term **--default-registry-url=\<default-registry-url\>:**

*Default registry URL to use, instead of the registries.json configuration file.*


- term **--configuration=\<configuration\>:**

*Build with configuration*


- term **--=\<Xcc\>:**

*Pass flag through to all C compiler invocations.*


- term **--=\<Xswiftc\>:**

*Pass flag through to all Swift compiler invocations.*


- term **--=\<Xlinker\>:**

*Pass flag through to all linker invocations.*


- term **--=\<Xcxx\>:**

*Pass flag through to all C++ compiler invocations.*


- term **--triple=\<triple\>:**


- term **--sdk=\<sdk\>:**


- term **--toolchain=\<toolchain\>:**


- term **--swift-sdk=\<swift-sdk\>:**

*Filter for selecting a specific Swift SDK to build with.*


- term **--sanitize=\<sanitize\>:**

*Turn on runtime checks for erroneous behavior, possible values: address, thread, undefined, scudo.*


- term **--auto-index-store|enable-index-store|disable-index-store:**

*Enable or disable indexing-while-building feature.*


- term **--enable-parseable-module-interfaces:**


- term **--jobs=\<jobs\>:**

*The number of jobs to spawn in parallel during the build process.*


- term **--use-integrated-swift-driver:**


- term **--explicit-target-dependency-import-check=\<explicit-target-dependency-import-check\>:**

*A flag that indicates this build should check whether targets only import their explicitly-declared dependencies.*


- term **--experimental-explicit-module-build:**


- term **--build-system=\<build-system\>:**


- term **--=\<debug-info-format\>:**

*The Debug Information Format to use.*


- term **--enable-dead-strip|disable-dead-strip:**

*Disable/enable dead code stripping by the linker.*


- term **--disable-local-rpath:**

*Disable adding $ORIGIN/@loader_path to the rpath by default.*


- term **--version:**

*Show the version.*


- term **--help:**

*Show help information.*

