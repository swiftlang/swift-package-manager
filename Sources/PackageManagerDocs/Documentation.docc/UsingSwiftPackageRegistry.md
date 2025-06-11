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

The JSON key `[default]` means that the registry at `https://packages.example.com` is "unscoped" and will be applied when there is no registry association found for a given scope. 

In this example, `https://packages.example.com` will be applied to all scopes.

### Adding a registry package dependency

A registry package dependency is declared in `Package.swift` using the package identifier.
For example: 

```swift
dependencies: [
    .package(id: "mona.LinkedList", .upToNextMajor(from: "1.0.0")),
],
```

Package manager will query the registry mapped to a package's scope to resolve and download the appropriate release version.

### Registry authentication

If a registry requires authentication, it can be set up by using the [`swift package-registry login`](<doc:PackageRegistryLogin>) subcommand introduced by [SE-0378](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0378-package-registry-auth.md#new-login-subcommand).

Currently, basic and token authentication are supported.

Provide the credentials either by setting the corresponding options (i.e., one of username/password or access token) or when prompted:

```bash
$ swift package-registry login https://packages.example.com
```

Package manager will save the credentials to the operating system's credential store (e.g., Keychain in macOS) or netrc file (which by default is located at `~/.netrc`) and apply them automatically when making registry API requests.

### Dependency Resolution Using Registry

Resolving a registry dependency involves these steps:
1. Fetch a package's available versions by calling the [list package releases](<doc:RegistryServerSpecification#4.1.-List-package-releases>) API.
2. Compute the dependency graph by [fetching manifest(s) for a package release](<doc:RegistryServerSpecification#4.3.-Fetch-manifest-for-a-package-release>).
3. Pinpoint the package version to use.

For more information on resolving dependencies, see <doc:ResolvingPackageVersions>. 

#### Using registry for source control dependencies

Here is an example of a source control dependency:

```swift
dependencies: [
    .package(url: "https://github.com/mona/LinkedList", .upToNextMajor(from: "1.0.0")),
],
```

Registry can be used for source control dependencies as well. 
This is particularly useful when there is a "mixed" graph (i.e., a dependency graph that has both source control and registry dependencies).
Package manager considers packages with different origins to be different, so if a package is referenced as both a registry (e.g., `mona.LinkedList`) and source control (e.g., `https://github.com/mona/LinkedList`) dependency, they are considered different even though they are the same package, and would result in symbol clashes.

Swift Package Manager can deduplicate packages by performing a [lookup on the source control URL](<doc:RegistryServerSpecification#4.5.-Lookup-package-identifiers-registered-for-a-URL>) (e.g., `https://github.com/mona/LinkedList`) to see if it is associated with any package identifier (e.g., `mona.LinkedList`).

One can control if/how Package manager should use registry in conjunction with source control dependencies by setting one of these flags:
- `--disable-scm-to-registry-transformation` (default): Swift Package Manager will not transform source control dependency to registry dependency. Source control dependency will be downloaded from its corresponding URL, while registry dependency will be resolved and downloaded using the configured registry (if any).
- `--use-registry-identity-for-scm`: Swift Package Manager will look up source control dependencies in the registry and use their registry identity whenever possible to help deduplicate packages across the two origins. In other words, suppose `mona.LinkedList` is the package identifier for `https://github.com/mona/LinkedList`, then Package manager will treat both references in the dependency graph as the same package. 
- `--replace-scm-with-registry`: Swift Package Manager will look up source control dependencies in the registry and use the registry to retrieve them instead of source control when possible. In other words, Package manager will attempt to download a source control dependency from the registry first, and fall back to cloning the source repository if the dependency is not found in the registry.

### Dependency Download From Registry

After a registry dependency is resolved, Swift Package Manager can [download source archive](<doc:RegistryServerSpecification#4.4.-Download-source-archive>) of the computed package version from the registry.

#### Package security

As a security feature, Swift Package Manager performs checksum TOFU ([trust-on-first-use](https://en.wikipedia.org/wiki/Trust_on_first_use)) on the downloaded source archive. See <doc:PackageSecurity> for more information about Package manager's use of trust-on-first-use.

#### Validating signed packages

 [SE-0391](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-signing) adds package signing support to Swift Package Manager.
Package manager determines if a downloaded archive is signed by checking for presence of the `X-Swift-Package-Signature-Format` and `X-Swift-Package-Signature` headers in the HTTP response.

 Swift Package Manager then performs a series of validations based on user's [security configuration](<doc:#Security-configuration>).

For more information on Package manager's registry security features, see <doc:PackageSecurity#Signed-packages-from-a-registry>.

### Publishing to Registry

 [`swift package-registry publish`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#new-package-registry-publish-subcommand) is an all-in-one command for publishing a package release to registry. 

#### Package signing

Registries can optionally require signing.
For more details on signed registry packages, see <doc:PackageSecurity#Signed-packages-from-a-registry>.

##### Signature formats

| Signature Format | Specification |
| ---------------- | ------------- |
| `cms-1.0.0`      | [SE-391](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-signature-format-cms-100) |

Since there is only one supported signature format, all signatures produced by Swift Package Manager are in `cms-1.0.0`.

##### Signed contents

###### Source archive

The signature is detached and sent as part of the HTTP request to the publish API. It is included in the source archive download response as HTTP headers, and is part of the package release metadata.

###### Package release metadata

The signature is detached and sent as part of the HTTP request to the publish API.
The current API specification does not include an endpoint for fetching this metadata in its original form.

For more details, refer to the [registry specification](<doc:RegistryServerSpecification#4.2.2.-Package-release-metadata-standards>).

###### Package manifest(s)

`Package.swift` and version-specific manifests are individually signed.
The signature is embedded in the corresponding manifest file.
The source archive is generated and signed **after** manifest signing. 

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

When a manifest is fetched from the registry, Swift Package Manager checks if the containing source archive is signed by fetching the package release metadata.
It is a failure if the source archive is signed but the manifest is not.
Package manager will extract and parse signature from the manifest then validate it similar to what is done for [source archive signature](<doc:Validating-signed-packages>).

Package manager performs publisher TOFU to ensure it remains consistent for the package. 
This implies the signer of manifests and source archive must be the same.

To reduce the amount of logging and thus noise, diagnostics related to manifest signature validation are set to DEBUG level. 
Only when user chooses the `prompt` option for unsigned packages or packages signed with an untrusted certificate would Package manager behave like source archive validation.  

### Swift Package Manager Registry Configuration

#### Registry-to-scope mappings

When resolving or downloading registry packages, Package manager looks at the registry-to-scope mappings in project and user-level configuration to determine which registry is assigned for a package's scope.

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

Registry security configurations are specified in the user-level `registries.json` (`~/.swiftpm/configuration/registries.json`):

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

There are multiple levels of overrides.
A configuration for a package is computed using values from the following (in descending precedence):
1. `packageOverrides` (if any)
1. `scopeOverrides` (if any)
1. `registryOverrides` (if any)
1. `default`

The `default` JSON object in the example above contains all configurable security options and their default value when there is no override.

- `signing.onUnsigned`: Indicates how Package manager will handle an unsigned package.

  | Option        | Description                                               |
  | ------------- | --------------------------------------------------------- |
  | `error`       | Package manager will reject the package and fail the build. |
  | `prompt`      | Package manager will prompt user to see if the unsigned package should be allowed. <ul><li>If no, Package manager will reject the package and fail the build.</li><li>If yes and the package has never been downloaded, its checksum will be stored for [checksum TOFU](<doc:PackageSecurity#Trust-on-First-Use>). Otherwise, if the package has been downloaded before, its checksum must match the previous value or else Package manager will reject the package and fail the build.</li></ul> Package manager will record user's response to prevent repetitive prompting. |
  | `warn`        | Package manager will not prompt user but will emit a warning before proceeding. |
  | `silentAllow` | Package manager will allow the unsigned package without prompting user or emitting warning. |

- `signing.onUntrustedCertificate`: Indicates how Package manager will handle a package signed with an [untrusted certificate](<doc:PackageSecurity#Trusted-vs-untrusted-certificate>).

  | Option        | Description                                               |
  | ------------- | --------------------------------------------------------- |
  | `error`       | Package manager will reject the package and fail the build. |
  | `prompt`      | Package manager will prompt user to see if the package signed with an untrusted certificate should be allowed. <ul><li>If no, Package manager will reject the package and fail the build.</li><li>If yes, Package manager will proceed with the package as if it were an unsigned package.</li></ul> Package manager will record user's response to prevent repetitive prompting. |
  | `warn`        | Package manager will not prompt user but will emit a warning before proceeding. |
  | `silentAllow` | Package manager will allow the package signed with an untrusted certificate without prompting user or emitting warning. |

- `signing.trustedRootCertificatesPath`: Absolute path to the directory containing custom trusted roots. Package manager will include these roots in its [trust store](<doc:PackageSecurity#Trusted-vs-untrusted-certificate>), and certificates used for package signing must chain to roots found in this store. This configuration allows override at the package, scope, and registry levels.
- `signing.includeDefaultTrustedRootCertificates`: Indicates if Package manager should include default trusted roots in its [trust store](<doc:PackageSecurity#Trusted-vs-untrusted-certificate>). This configuration allows override at the package, scope, and registry levels.
- `signing.validationChecks`: Validation check settings for the package signature.

  | Validation               | Description                                               |
  | ------------------------ | --------------------------------------------------------------- |
  | `certificateExpiration`  | <ul><li>`enabled`: Package manager will check that the current timestamp when downloading falls within the signing certificate's validity period. If it doesn't, Package manager will reject the package and fail the build.</li><li>`disabled`: Package manager will not perform this check.</li></ul> |
  | `certificateRevocation`  | With the exception of `disabled`, Package manager will check revocation status of the signing certificate. Currently, Package manager only supports revocation check done through [OCSP](https://www.rfc-editor.org/rfc/rfc6960).<ul><li>`strict`: Revocation check must complete successfully and the certificate must be in good status. Package manager will reject the package and fail the build if the revocation status is revoked or unknown (including revocation check not supported or failed).</li><li>`allowSoftFail`: Package manager will reject the package and fail the build iff the certificate has been revoked. Package manager will allow the certificate's revocation status to be unknown (including revocation check not supported or failed).</li><li>`disabled`: Package manager will not perform this check.</li></ul> |
