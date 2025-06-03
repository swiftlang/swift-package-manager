# Using a package registry

Configure and use a package registry for Swift Package Manager.

## Overview

Swift Package Manager supports downloading dependencies from any package registry that implements 
[SE-0292](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0292-package-registry-service.md)
and the corresponding [service specification](<doc:RegistryServerSpecification>).

In a registry, packages are identified by [package identifier](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0292-package-registry-service.md#package-identity)
in the form of `scope.package-name`.

### Configuring a registry

A registry can be configured in Swift Package Manager at two levels:
 - Project: the registry will be used for packages within the project. Settings are stored in `.swiftpm/configuration/registries.json`.
 - User: the registry will be used for all projects for the user. Settings are stored in `~/.swiftpm/configuration/registries.json`.

One could use the [`swift package-registry set` subcommand](<doc:PackageRegistrySet>) to assign a registry URL:

```bash
$ swift package-registry set https://packages.example.com 
```

The above sets registry to `https://packages.example.com` at project level. Pass 
the `--global` option to set registry at user level:

```bash
$ swift package-registry set --global https://packages.example.com 
```

The resulting `registries.json` would look something like:

```json
{
  "registries" : {
    "[default]" : {
      "url": "https://packages.example.com"
    }   
  },
  "version" : 1
}
```

The JSON key `[default]` means that the registry at `https://packages.example.com` is 
"unscoped" and will be applied when there is no registry association found for 
a given scope. 

In this example, `https://packages.example.com` will be applied to all scopes.

### Adding a registry package dependency

A registry package dependency is declared in `Package.swift` using the package identifier.
For example: 

```swift
dependencies: [
    .package(id: "mona.LinkedList", .upToNextMajor(from: "1.0.0")),
],
```

The package manager will query the registry mapped to a package's scope to resolve and download the appropriate release version.

### Registry authentication

If a registry requires authentication, it can be set up by using the [`swift package-registry login` subcommand](<doc:PackageRegistryLogin>) introduced by SE-0378.

Currently, basic and token authentication are supported.

Provide the credentials either by setting the corresponding options
(i.e., one of username/password or access token) or when prompted:

```bash
$ swift package-registry login https://packages.example.com
```

The package manager will save the credentials to the operating system's credential store
(e.g., Keychain in macOS) or netrc file (which by default is located at `~/.netrc`) 
and apply them automatically when making registry API requests.

### Dependency Resolution Using Registry

Resolving a registry dependency involves these steps:
1. Fetch a package's available versions by calling the [list package releases](<doc:RegistryServerSpecification#4.1.-List-package-releases>) API.
2. Compute the dependency graph by [fetching manifest(s) for a package release](<doc:RegistryServerSpecification#4.3.-Fetch-manifest-for-a-package-release>).
3. Pinpoint the package version to use.

#### Using registry for source control dependencies

Here is an example of a source control dependency:

```swift
dependencies: [
    .package(url: "https://github.com/mona/LinkedList", .upToNextMajor(from: "1.0.0")),
],
```

Registry can be used for source control dependencies as well. 
This is particularly useful when there is a "mixed" graph (i.e., a dependency graph that has both source control and registry dependencies).
The package manager considers packages with different origins to be different, so if a package is referenced as both a registry (e.g., `mona.LinkedList`) and source control (e.g., `https://github.com/mona/LinkedList`) dependency, they are considered different even though they are the same package, and would result in symbol clashes.

Swift Package Manager can deduplicate packages by performing a [lookup on the source control URL](<doc:RegistryServerSpecification#4.5.-Lookup-package-identifiers-registered-for-a-URL>) (e.g., `https://github.com/mona/LinkedList`) to see if it is associated with any package identifier (e.g., `mona.LinkedList`).

One can control if/how the package manager should use registry in conjunction with source control dependencies by setting one of these flags:
- `--disable-scm-to-registry-transformation` (default): Swift Package Manager will not transform source control dependency to registry dependency. Source control dependency will be downloaded from its corresponding URL, while registry dependency will be resolved and downloaded using the configured registry (if any).
- `--use-registry-identity-for-scm`: Swift Package Manager will look up source control dependencies in the registry and use their registry identity whenever possible to help deduplicate packages across the two origins. In other words, suppose `mona.LinkedList` is the package identifier for `https://github.com/mona/LinkedList`, then the package manager will treat both references in the dependency graph as the same package. 
- `--replace-scm-with-registry`: Swift Package Manager will look up source control dependencies in the registry and use the registry to retrieve them instead of source control when possible. In other words, the package manager will attempt to download a source control dependency from the registry first, and fall back to cloning the source repository if the dependency is not found in the registry.

### Dependency Download From Registry

After a registry dependency is resolved, Swift Package Manager can [download source archive](<doc:RegistryServerSpecification#4.4.-Download-source-archive>) of the computed package version from the registry.

#### Checksum TOFU

As a [security feature](<doc:PackageSecurity#Trust-on-First-Use>), Swift Package Manager performs checksum TOFU  ([trust-on-first-use](https://en.wikipedia.org/wiki/Trust_on_first_use)) on the downloaded source archive.
<!--If the archive is downloaded for the first time, the package manager [fetches metadata of the package release](<doc:RegistryServerSpecification#4.2.-Fetch-information-about-a-package-release>) to obtain the expected checksum.-->
<!--Otherwise, the package manager compares the checksum with that in local storage (`~/.swiftpm/security/fingerprints/`) saved from previous download.-->

<!--If checksum of the downloaded archive doesn't match the expected-->
<!--or previous value, SwiftPM will fail the build. This can be-->
<!--tuned down from error to warning by setting the build option -->
<!--`--resolver-fingerprint-checking` to `warn` (default is `strict`).-->

<!--Checksum TOFU is also done for manifests downloaded from registry. -->

#### Validating signed packages

 [SE-0391](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-signing) adds package signing support to Swift Package Manager.
The package manager determines if a downloaded archive is signed by checking for presence of the `X-Swift-Package-Signature-Format` and `X-Swift-Package-Signature`
 headers in the HTTP response.

 Swift Package Manager then performs a series of validations based on user's
 [security configuration](<doc:#Security-configuration>).
 - If the archive is unsigned, the package manager will error/prompt/warn/allow based on the `signing.onUnsigned` configuration. 
 - If the archive is signed, the package manager will validate the signature and the signing certificate chain. (see the following sections for details)

##### Trusted vs. untrusted certificate

A certificate is trusted if it is chained to any root in Swift Package Manager's trust store, which consists of:
- Swift Package Manager's default trust store, if `signing.includeDefaultTrustedRootCertificates` is `true`.
- Custom root(s) in the configured trusted roots directory at `signing.trustedRootCertificatesPath`. Certificates must be DER-encoded.

Otherwise, a certificate is untrusted and handled according to the `signing.onUntrustedCertificate` configuration. 
If user opts to continue with the untrusted certificate, the package manager will proceed with the archive as if it were an unsigned package.

##### Certificate policies

Swift Package Manager requires all certificates used for package signing to have the "code signing" extended key usage extension. They must also satisfy the core policies from [RFC 5280](https://www.rfc-editor.org/rfc/rfc5280), as implemented by [swift-certificates](https://github.com/apple/swift-certificates). 

User can configure certificate expiry and revocation check through the `signing.validationChecks.certificateExpiration` and `signing.validationChecks.certificateRevocation` configuration, respectively. Note that revocation check implicitly requires expiry check.
   
An invalid signing certificate would result in the package manager rejecting the archive.

##### Publisher TOFU

Some certificates allow the package manager to extract additional information about the signing identity. For packages signed with these certificates, the package manager will perform publisher TOFU to ensure the signer remains the same across all versions of the package. 

The `--resolver-signing-entity-checking` option controls whether publisher mismatch should result in a warning (`warn`) or error (`strict`). Data used by publisher TOFU is saved to `~/.swiftpm/security/signing-entities/`.

### Publishing to Registry

 [`swift package-registry publish`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#new-package-registry-publish-subcommand)
 is an all-in-one command for publishing a package release to registry.

#### Package release metadata

Package authors can specify a custom location of the package 
release metadata file by setting the `--metadata-path` option 
of the [`publish` subcommand](<doc:PackageRegistryPublish>). Otherwise, by default the package manager 
looks for a file named `package-metadata.json` in the 
package directory.

Contents of the metadata file must conform to the 
[JSON schema](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-release-metadata-standards)
defined in SE-0391. Also refer to registry documentation 
for any additional requirements.

#### Package signing
 
A registry may support or require signing. To sign a package
release, package author will need to set either the `signing-identity`
(for reading from operating system's identity store such as Keychain in macOS),
or `private-key-path` and `cert-chain-paths` (for reading from files)
options of the `publish` subcommand such that the package manager can
locate the signing key and certificate.

If the certificate chain's root and intermediates are known by the package manager,
then package author would only need to provide the leaf signing
certificate in `cert-chain-paths`. 

Otherwise, the entire certificate chain should be provided as 
`cert-chain-paths` so that all of the certificates will be 
included in the signature and make it possible for the package manager 
to reconstruct the certificate chain for validation later. 
This is applicable to `signing-identity` as well 
(i.e., `signing-identity` can be used in combination with 
`cert-chain-paths` to provide the entire certificate chain).

If the root of the signing certificate is not in the package manager's
default trust store, package author is responsible for 
telling package users to include the root certificate in their local 
[trust roots](<doc:Trusted-vs-untrusted-certificate>) 
directory, or else [signature validation](<doc:Validating-signed-packages>) 
may fail upon download because the signing certificate is not trusted.

<!-- TODO bp: remove this-->
Refer to registry documentation for its certificate policy.

##### Signature formats

| Signature Format | Specification |
| ---------------- | ------------- |
| `cms-1.0.0`      | [SE-391](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-signature-format-cms-100) |

Since there is only one supported signature format, all signatures produced by Swift Package Manager are in `cms-1.0.0`.

##### Signed contents

###### Source archive

The signature is detached and sent as part of the HTTP request to the
publish API. It is included in the source archive download response as
HTTP headers, and is part of the package release metadata.

###### Package release metadata

The signature is detached and sent as part of the HTTP request to the
publish API. The current API specification does not include an endpoint
for fetching this metadata in its original form.

###### Package manifest(s)

`Package.swift` and version-specific manifests are individually signed.
The signature is embedded in the corresponding manifest file. The source
archive is generated and signed **after** manifest signing. 

```swift
// swift-tools-version: 5.7

import PackageDescription
let package = Package(
    name: "library",
    products: [ .library(name: "library", targets: ["library"]) ],
    targets: [ .target(name: "library") ]
)

// signature: cms-1.0.0;l1TdTeIuGdNsO1FQ0ptD64F5nSSOsQ5WzhM6/7KsHRuLHfTsggnyIWr0DxMcBj5F40zfplwntXAgS0ynlqvlFw==
```

When a manifest is fetched from the registry, Swift Package Manager checks if the
containing source archive is signed by fetching the package release 
metadata. It is a failure if the source archive is signed but the 
manifest is not. The package manager will extract and parse signature from 
the manifest then validate it similar to what is done for 
[source archive signature](<doc:Validating-signed-packages>).

The package manager performs publisher TOFU to ensure it remains consistent
for the package. This implies the signer of manifests and source
archive must be the same.

To reduce the amount of logging and thus noise, diagnostics related 
to manifest signature validation are set to DEBUG level. Only when 
user chooses the `prompt` option for unsigned packages or packages 
signed with an untrusted certificate would the package manager behave like 
source archive validation.  

### Swift Package Manager Registry Configuration

#### Registry-to-scope mappings

When resolving or downloading registry packages, the package manager looks at the
registry-to-scope mappings in project and user-level configuration to
determine which registry is assigned for a package's scope.

For example, given the following configuration files:

```json
// User-level configuration (~/.swiftpm/configuration/registries.json)
{
  "registries": {
    "[default]": {
      "url": "https://global.example.com"
    },
    "foo": {
      "url": "https://global.example.com"
    },
  },
  "version": 1
}

// Local configuration (.swiftpm/configuration/registries.json)
{
  "registries": {
    "foo": {
      "url": "https://local.example.com"
    }
  },
  "version": 1
}
```

- For package `foo.LinkedList`, the registry at `https://local.example.com` is used. (Local configuration has higher precedence than user-level configuration.)
- For package `bar.LinkedList`, the registry at `https://global.example.com` is used. (No mapping for scope `bar` is found, so `[default]` is used.)
  
#### Security configuration

Registry security configuration are specified in the user-level `registries.json`
(`~/.swiftpm/configuration/registries.json`):

```json
{
  "security": {
    "default": {
      "signing": {
        "onUnsigned": "prompt", // One of: "error", "prompt", "warn", "silentAllow"
        "onUntrustedCertificate": "prompt", // One of: "error", "prompt", "warn", "silentAllow"
        "trustedRootCertificatesPath": "~/.swiftpm/security/trusted-root-certs/",
        "includeDefaultTrustedRootCertificates": true,
        "validationChecks": {
          "certificateExpiration": "disabled", // One of: "enabled", "disabled"
          "certificateRevocation": "disabled"  // One of: "strict", "allowSoftFail", "disabled"
        }
      }
    },
    "registryOverrides": {
      // The example shows all configuration overridable at registry level
      "packages.example.com": {
        "signing": {
          "onUnsigned": "warn",
          "onUntrustedCertificate": "warn",
          "trustedRootCertificatesPath": <STRING>,
          "includeDefaultTrustedRootCertificates": <BOOL>,
          "validationChecks": {
            "certificateExpiration": "enabled",
            "certificateRevocation": "allowSoftFail"
          }
        }
      }
    },
    "scopeOverrides": {
      // The example shows all configuration overridable at scope level
      "mona": {
        "signing": {
          "trustedRootCertificatesPath": <STRING>,
          "includeDefaultTrustedRootCertificates": <BOOL>
        }
      }
    },
    "packageOverrides": {
      // The example shows all configuration overridable at package level
      "mona.LinkedList": {
        "signing": {
          "trustedRootCertificatesPath": <STRING>,
          "includeDefaultTrustedRootCertificates": <BOOL>
        }
      }
    }
  },
  ...
}
```

There are multiple levels of overrides. Configuration for a 
package is computed using values from the following 
(in descending precedence):
1. `packageOverrides` (if any)
1. `scopeOverrides` (if any)
1. `registryOverrides` (if any)
1. `default`

The `default` JSON object in the example above contains all 
configurable security options and their default value when 
there is no override.

- `signing.onUnsigned`: Indicates how the package manager will handle an unsigned package.

  | Option        | Description                                               |
  | ------------- | --------------------------------------------------------- |
  | `error`       | The package manager will reject the package and fail the build. |
  | `prompt`      | The package manager will prompt user to see if the unsigned package should be allowed. <ul><li>If no, The package manager will reject the package and fail the build.</li><li>If yes and the package has never been downloaded, its checksum will be stored for [checksum TOFU](<doc:Checksum-TOFU>). Otherwise, if the package has been downloaded before, its checksum must match the previous value or else the package manager will reject the package and fail the build.</li></ul> The package manager will record user's response to prevent repetitive prompting. |
  | `warn`        | The package manager will not prompt user but will emit a warning before proceeding. |
  | `silentAllow` | The package manager will allow the unsigned package without prompting user or emitting warning. |

- `signing.onUntrustedCertificate`: Indicates how The package manager will handle a package signed with an [untrusted certificate](<doc:Trusted-vs-untrusted-certificate>).

  | Option        | Description                                               |
  | ------------- | --------------------------------------------------------- |
  | `error`       | The package manager will reject the package and fail the build. |
  | `prompt`      | The package manager will prompt user to see if the package signed with an untrusted certificate should be allowed. <ul><li>If no, the package manager will reject the package and fail the build.</li><li>If yes, the package manager will proceed with the package as if it were an unsigned package.</li></ul> The package manager will record user's response to prevent repetitive prompting. |
  | `warn`        | The package manager will not prompt user but will emit a warning before proceeding. |
  | `silentAllow` | The package manager will allow the package signed with an untrusted certificate without prompting user or emitting warning. |

- `signing.trustedRootCertificatesPath`: Absolute path to the directory containing custom trusted roots. The package manager will include these roots in its [trust store](<doc:Trusted-vs-untrusted-certificate>), and certificates used for package signing must chain to roots found in this store. This configuration allows override at the package, scope, and registry levels.
- `signing.includeDefaultTrustedRootCertificates`: Indicates if the package manager should include default trusted roots in its [trust store](<doc:Trusted-vs-untrusted-certificate>). This configuration allows override at the package, scope, and registry levels.
- `signing.validationChecks`: Validation check settings for the package signature.

  | Validation               | Description                                               |
  | ------------------------ | --------------------------------------------------------------- |
  | `certificateExpiration`  | <ul><li>`enabled`: The package manager will check that the current timestamp when downloading falls within the signing certificate's validity period. If it doesn't, the package manager will reject the package and fail the build.</li><li>`disabled`: The package manager will not perform this check.</li></ul> |
  | `certificateRevocation`  | With the exception of `disabled`, the package manager will check revocation status of the signing certificate. Currently, the package manager only supports revocation check done through [OCSP](https://www.rfc-editor.org/rfc/rfc6960).<ul><li>`strict`: Revocation check must complete successfully and the certificate must be in good status. The package manager will reject the package and fail the build if the revocation status is revoked or unknown (including revocation check not supported or failed).</li><li>`allowSoftFail`: The package manager will reject the package and fail the build iff the certificate has been revoked. The package manager will allow the certificate's revocation status to be unknown (including revocation check not supported or failed).</li><li>`disabled`: The package manager will not perform this check.</li></ul> |
