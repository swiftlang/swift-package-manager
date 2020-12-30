# Swift Package Registry Service Specification

- [1. Notations](#1-notations)
- [2. Definitions](#2-definitions)
- [3. Conventions](#3-conventions)
  - [3.1. Application layer protocols](#31-application-layer-protocols)
  - [3.2. Authentication](#32-authentication)
  - [3.3. Error handling](#33-error-handling)
  - [3.4. Rate limiting](#34-rate-limiting)
  - [3.5. API versioning](#35-api-versioning)
  - [3.6. Package name resolution](#36-package-name-resolution)
- [4. Endpoints](#4-endpoints)
  - [4.1. List package releases](#41-list-package-releases)
    - [4.1.1. Content negotiation](#411-content-negotiation)
  - [4.2. Fetch metadata for a package release](#42-fetch-metadata-for-a-package-release)
    - [4.2.1. Package release metadata data standards](#421-package-release-metadata-data-standards)
  - [4.3. Fetch manifest for a package release](#43-fetch-manifest-for-a-package-release)
    - [4.3.1. swift-version query parameter](#431-swift-version-query-parameter)
  - [4.4. Fetch source archive](#44-fetch-source-archive)
    - [4.4.1. Integrity verification](#441-integrity-verification)
    - [4.4.2. Download locations](#442-download-locations)
- [5. Normative References](#5-normative-references)
- [6. Informative References](#6-informative-references)

## 1. Notations

The following terminology and conventions are used in this document.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL"
in this document are to be interpreted as described in [RFC 2119].

This specification uses the Augmented Backus-Naur Form (ABNF) notation
as described in [RFC 5234].

API endpoints that accept parameters in their path
are expressed by Uniform Resource Identifier (URI) templates,
as described in [RFC 6570].

## 2. Definitions

The following terms, as used in this document, have the meanings indicated.

- _Package_:
  A named collection of Swift source code
  that is organized into one or more modules
  according to a `Package.swift` manifest file.
- _Release_:
  The state of a package after applying a particular set of changes
  that is uniquely identified by an assigned version number.
- _Version Number_:
  An identifier for a package release
  in accordance with the [Semantic Versioning Specification (SemVer)][SemVer].

## 3. Conventions

This document uses the following conventions
in its description of client-server interactions.

### 3.1. Application layer protocols

A client and server MUST communicate over a secured connection
using Transport Layer Security (TLS) with the `https` URI scheme.

The use of HTTP 1.1 in examples is non-normative.
A client and server MAY communicate according to this specification
using any version of the HTTP protocol.

### 3.2. Authentication

A server SHOULD require authentication
for client requests to publish a package release.
A server MAY require authentication
for client requests to access information about packages and package releases.

A server SHOULD respond with a status code of `401` (Unauthorized)
if a client sends a request to an endpoint that requires authentication
without providing credentials.
A server MAY respond with a status code of `404` (Not Found) or `403` (Forbidden)
when a client provides valid credentials
but isn't authorized to access the requested resource.

A server MAY use any authentication model of its choosing.
However, the use of a scoped, revocable authorization framework
like [OAuth 2.0][RFC 6749] is RECOMMENDED.

### 3.3. Error handling

A server SHOULD communicate any errors to the client
using "problem details" objects,
as described by [RFC 7807].
For example,
a client sends a request to create a package release
with an invalid `tag` parameter
and receives the following response:

```http
HTTP/1.1 404
Content-Version: 1
Content-Type: application/problem+json
Content-Language: en

{
   "detail": "tag '2.0.0' not found"
}
```

### 3.4. Rate limiting

A server MAY limit the number of requests made by a client
by responding with a status code of `429` (Too Many Requests).

```http
HTTP/1.1 429
Content-Version: 1
Content-Type: application/problem+json
Content-Language: en
Retry-After: 60

{
   "detail": "try again in 60 seconds"
}
```

A client SHOULD follow the guidance of any
`Retry-After` header values provided in responses
to prevent overwhelming a server with retry requests.
It is RECOMMENDED for clients to introduce randomness in their retry logic
to avoid a [thundering herd effect].

### 3.5. API versioning

Package registry APIs are versioned.

API version numbers are designated by decimal integers.
The accepted version of this proposal constitutes the initial version, `1`.
Subsequent revisions SHOULD be numbered sequentially
(`2`, `3`, and so on).

API version numbers SHOULD follow
Semantic Versioning conventions for major releases.
Non-breaking changes, such as
adding new endpoints,
adding new optional parameters to existing endpoints,
or adding new information to existing endpoints in a backward-compatible way,
SHOULD NOT require a new version.
Breaking changes, such as
removing or changing an existing endpoint
in a backward-incompatible way,
MUST correspond to a new version.

A client SHOULD set the `Accept` header field
to specify the API version of a request.

```http
GET /github.com/mona/LinkedList/list HTTP/1.1
Host: packages.example.com
Accept: application/vnd.swift.registry.v1+json
```

Valid `Accept` header field values are described by the following rules:

```abnf
    version     = "1"       ; The API version
    mediatype   = "json" /  ; JSON (default media type)
                  "zip"  /  ; Zip archives, used for package releases
                  "swift"   ; Swift file, used for package manifest
    accept      = "application/vnd.swift.registry" [".v" version] ["+" mediatype]
```

A server SHALL set the `Content-Type` and `Content-Version` header fields
with the corresponding content type and API version number of the response.

```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Version: 1
```

If a client sends a request without an `Accept` header,
a server MAY either return `400 Bad Request` or
process the request using an API version that it chooses,
making sure to set the `Content-Type` and `Content-Version` headers accordingly.

If a client sends a request with an `Accept` header
that specifies an unknown or invalid API version,
a server SHOULD respond with a status code of `400` (Bad Request).

```http
HTTP/1.1 400 Bad Request
Content-Version: 1
Content-Type: application/problem+json
Content-Language: en

{
   "detail": "invalid API version"
}
```

If a client sends a request with an `Accept` header
that specifies a valid but unsupported API version,
a server SHOULD respond with a status code of `415` (Unsupported Media Type).

```http
HTTP/1.1 415 Unsupported Media Type
Content-Version: 1
Content-Type: application/problem+json
Content-Language: en

{
   "detail": "unsupported API version"
}
```

### 3.6. Package name resolution

A package may declare external packages as dependencies in its manifest.
Each package dependency may specify a requirement
on which versions are allowed.

> In Swift 5.2,
> the `PackageDescription` framework adds an optional `name` parameter
> to the `package` methods used to declare dependencies.
> If unspecified,
> the last path component of the dependency URL is used
> (for example, `github.com/mona/LinkedList` becomes `LinkedList`).
> This name is used only to disambiguate between packages
> as they're listed in the `dependencies` field of a `target` declaration
> and has no impact on how a package's modules are referenced in code.

An external package dependency may itself have
one or more external package dependencies,
known as <dfn>transitive dependencies</dfn>.
When multiple packages have dependencies in common,
Swift Package Manager determines which version of that package should be used
(if any exist that satisfy all specified requirements)
in a process called <dfn>package resolution</dfn>.

Each external package is uniquely identified
by the canonical URL of its source code.
Therefore,
a package is a shared dependency of two packages
if and only if both of them declare an external dependency with the same URL.

For the purposes of package resolution,
package URLs are
case-insensitive
(for example, `mona` ≍ `MONA`)
and normalization-insensitive
(for example, `n` + `◌̃` ≍ `ñ`).
Further normalization may be done
to determine URL equivalence,
but the exact behavior is considered beyond the scope of this proposal
and left as an implementation detail of Swift Package Manager.
For additional guidance, see
[RFC 3986] § 6.1 "Equivalence"
and the research article
["Do not crawl in the DUST: Different URLs with similar text"][DUST].

A client MAY use other techniques
to determine that two dependencies are equivalent,
such as comparing their contents, structure or history.

## 4. Endpoints

A server MUST respond to the following endpoints:

| Link                 | Method | Path                                                 | Description                                   |
| -------------------- | ------ | ---------------------------------------------------- | --------------------------------------------- |
| [\[1\]](#endpoint-1) | `GET`  | `/{package}`                                         | List package releases                         |
| [\[2\]](#endpoint-2) | `GET`  | `/{package}/{version}`                               | Fetch metadata for a package release          |
| [\[3\]](#endpoint-3) | `GET`  | `/{package}/{version}/Package.swift{?swift-version}` | Fetch manifest for a package release          |
| [\[4\]](#endpoint-4) | `GET`  | `/{package}/{version}.zip`                           | Download source archive for a package release |

A server SHOULD also respond to `HEAD` requests
for each of the specified endpoints.

* * *

<a name="endpoint-1"></a>

### 4.1. List package releases

A client MAY send a `GET` request
for a URI matching the expression `/{package}`
to retrieve a list of the available releases for a particular package.
A client SHOULD set the `Accept` header with
the `application/vnd.swift.registry.v1+json` content type
and MAY append the `.json` extension to the requested URI.

```http
GET /github.com/mona/LinkedList HTTP/1.1
Host: packages.example.com
Accept: application/vnd.swift.registry.v1+json
```

If a package is found for the requested URI,
a server SHOULD respond with a status code of `200` (OK)
and the `Content-Type` header `application/json`.
Otherwise, a server SHOULD respond with a status code of `404` (NOT FOUND).

A server SHOULD respond with a JSON document
containing all of the releases for the requested package.

```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Version: 1
Link: <https://github.com/mona/LinkedList>; rel="canonical",
      <https://packages.example.com/github.com/mona/LinkedList/1.1.1>; rel="latest-version",
      <https://github.com/sponsors/mona>; rel="payment"

{
    "releases": {
        "1.1.1": {
            "url": "https://packages.example.com/github.com/mona/LinkedList/1.1.1"
        },
        "1.1.0": {
            "url": "https://packages.example.com/github.com/mona/LinkedList/1.1.0",
            "problem": {
                "status": 410,
                "title": "Gone",
                "detail": "this release was removed from the registry"
            }
        },
        "1.0.0": {
            "url": "https://packages.example.com/github.com/mona/LinkedList/1.0.0"
        }
    }
}
```

The response body SHALL contain a JSON object
nested at a top-level `releases` key,
whose keys are version numbers for releases
and values are objects containing the following fields:

| Key       | Type   | Description                           | Requirement Level |
| --------- | ------ | ------------------------------------- | ----------------- |
| `url`     | String | A URI for the release                 | REQUIRED          |
| `problem` | Object | A [problem details][RFC 7807] object. | OPTIONAL          |

A server SHOULD communicate the unavailability of a package release
using a ["problem details"][RFC 7807] object.
A client SHOULD consider any releases with an associated `problem`
to be unavailable for the purposes of package resolution.

A server SHOULD respond with
a link to the latest published release of the package if one exists,
using a `Link` header field with a `latest-version` relation.

A server SHOULD list releases in order of precedence,
starting with the latest version.
However, a client SHOULD NOT assume
any specific ordering of version numbers in a response.

A server MAY include a `Link` entry with the `canonical` relation type
that locates the source repository of the package.

A server MAY paginate results by responding with
a `Link` header field that includes any of the following relations:

| Name    | Description                             |
| ------- | --------------------------------------- |
| `next`  | The immediate next page of results.     |
| `last`  | The last page of results.               |
| `first` | The first page of results.              |
| `prev`  | The immediate previous page of results. |

For example,
the `Link` header field in a response for the third page of paginated results:

```http
Link: <https://packages.example.com/github.com/mona/HashMap/5.0.3>; rel="latest-version",
      <https://packages.example.com/github.com/mona/HashMap?page=1>; rel="first",
      <https://packages.example.com/github.com/mona/HashMap?page=2>; rel="previous",
      <https://packages.example.com/github.com/mona/HashMap?page=4>; rel="next",
      <https://packages.example.com/github.com/mona/HashMap?page=10>; rel="last"
```

A server MAY respond with additional `Link` entries,
such as one with a `payment` relation for sponsoring a package maintainer.

#### 4.1.1. Content negotiation

A server that hosts the source repository for a package
on the same domain as a package registry
SHOULD respond to `GET` or `HEAD` requests for that source repository
with an `application/vnd.swift.registry` MIME type for
by redirecting to the corresponding endpoint for that package's releases.

For example,
if a server hosts the source code for a package at `github.com/mona/LinkedList`
and hosts a package registry service on the `swift.pkg.github.com` subdomain,
a client requesting the source code for that package
with the `Accept` header containing `application/vnd.swift.registry.v1+json`
should be redirected to the registry endpoint
that lists releases for that package.

```http
HEAD /mona/LinkedList HTTP/1.1
Host: github.com
Accept: application/vnd.swift.registry.v1+json,
        application/x-git-upload-pack-advertisement;q=0.7
```

```http
HTTP/1.1 303 See Other
Content-Version: 1
Location: https://swift.pkg.github.com/github.com/mona/LinkedList
```

A server MAY use any `User-Agent` header provided by a client
to proactively redirect to the corresponding Swift package releases endpoint.

```http
HEAD /mona/LinkedList HTTP/1.1
Host: github.com
User-Agent: swift package manager/5.4.0 (1200.0.00.0; x86_64-apple-darwin19.5.0)
```

```http
HTTP/1.1 303 See Other
Content-Version: 1
Location: https://swift.pkg.github.com/github.com/mona/LinkedList
```

A server MAY advertise package registry support to a client
requesting a package's source repository
by including a `Link` header in the response.

```http
HEAD /mona/LinkedList/archive/1.1.1.zip HTTP/1.1
Host: github.com
```

```http
HTTP/1.1 200 OK
Content-Type: text/html
Link: <https://swift.pkg.github.com/github.com/mona/LinkedList/1.1.1.zip>; rel="service"
```

<a name="endpoint-3"></a>

### 4.2. Fetch metadata for a package release

A client MAY send a `GET` request
for a URI matching the expression `/{package}/{version}`
to retrieve metadata about a release.
A client SHOULD set the `Accept` header with
the `application/vnd.swift.registry.v1+json` content type,
and MAY append the `.json` extension to the requested URI.

```http
GET /github.com/mona/LinkedList/1.1.1 HTTP/1.1
Host: packages.example.com
Accept: application/vnd.swift.registry.v1+json
```

If a release is found for the requested URI,
a server SHOULD respond with a status code of `200` (OK)
and the `Content-Type` header `application/json`.
Otherwise, a server SHOULD respond with a status code of `404` (NOT FOUND).

```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Version: 1
Link: <https://packages.example.com/mona/LinkedList/1.1.1>; rel="latest-version",
      <https://packages.example.com/mona/LinkedList/1.0.0>; rel="predecessor-version"
```

A server SHOULD respond with a `Link` header containing the following entries:

| Relation              | Description                                                    |
| --------------------- | -------------------------------------------------------------- |
| `latest-version`      | The latest published release of the package                    |
| `successor-version`   | The next published release of the package, if one exists       |
| `predecessor-version` | The previously published release of the package, if one exists |

A link with the `latest-version` relation
MAY correspond to the requested release.

#### 4.2.1. Package release metadata data standards

A server MAY include metadata fields in its package release response.
It is RECOMMENDED that package metadata be represented in [JSON-LD]
according to a structured data standard.
For example,
this response using the [Schema.org] [SoftwareSourceCode] vocabulary:

```jsonc
{
  "@context": ["http://schema.org/"],
  "@type": "SoftwareSourceCode",
  "name": "LinkedList",
  "description": "One thing links to another.",
  "keywords": ["data-structure", "collection"],
  "version": "1.1.1",
  "codeRepository": "https://github.com/mona/LinkedList",
  "license": "https://www.apache.org/licenses/LICENSE-2.0",
  "programmingLanguage": {
    "@type": "ComputerLanguage",
    "name": "Swift",
    "url": "https://swift.org"
  },
  "author": {
      "@type": "Person",
      "@id": "https://example.com/mona",
      "givenName": "Mona",
      "middleName": "Lisa",
      "familyName": "Octocat"
  }
}
```

<a name="endpoint-3"></a>

### 4.3. Fetch manifest for a package release

A client MAY send a `GET` request
for a URI matching the expression `/{package}/{version}/Package.swift`
to retrieve the package manifest for a release.
A client SHOULD set the `Accept` header to
`application/vnd.swift.registry.v1+swift`.

```http
GET /github.com/mona/LinkedList/1.1.1/Package.swift HTTP/1.1
Host: packages.example.com
Accept: application/vnd.swift.registry.v1+swift
```

If a release is found for the requested URI,
a server SHOULD respond with a status code of `200` (OK)
and the `Content-Type` header `text/x-swift`.
Otherwise, a server SHOULD respond with a status code of `404` (NOT FOUND).

```http
HTTP/1.1 200 OK
Cache-Control: public, immutable
Content-Type: text/x-swift
Content-Disposition: attachment; filename="Package.swift"
Content-Length: 361
Content-Version: 1
ETag: 87e749848e0fc4cfc509e4090ca37773
Link: <http://packages.example.com/github.com/mona/LinkedList/Package.swift?swift-version=4>; rel="alternate",
      <http://packages.example.com/github.com/mona/LinkedList/Package.swift?swift-version=4.2>; rel="alternate"

// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "LinkedList",
    products: [
        .library(name: "LinkedList", targets: ["LinkedList"])
    ],
    targets: [
        .target(name: "LinkedList"),
        .testTarget(name: "LinkedListTests", dependencies: ["LinkedList"]),
    ],
    swiftLanguageVersions: [.v4, .v5]
)
```

A server SHOULD respond with a `Content-Length` header
set to the size of the manifest in bytes.

A server SHOULD respond with a `Content-Disposition` header
set to `attachment` with a `filename` parameter equal to
the name of the manifest file
(for example, "Package.swift").

It is RECOMMENDED for clients and servers to support
caching as described by [RFC 7234].

A server SHOULD include `Link` header fields with the `alternate` relation type
for each additional file in the release's source archive
whose filename matches the following regular expression pattern:

```regexp
\APackage(@swift-(\d+)(?:\.(\d+)){0,2})?.swift\z
```

#### 4.3.1. swift-version query parameter

A client MAY specify a `swift-version` query parameter
to request a manifest for a particular version of Swift.

```http
GET /github.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4.2 HTTP/1.1
Host: packages.example.com
Accept: application/vnd.swift.registry.v1+swift
```

If the package includes a file named
`Package@swift-{swift-version}.swift`,
the server SHOULD respond with a status code of `200` (OK)
and the content of that file in the response body.

```http
HTTP/1.1 200 OK
Cache-Control: public, immutable
Content-Type: text/x-swift
Content-Disposition: attachment; filename="Package@swift-4.2.swift"
Content-Length: 361
Content-Version: 1
ETag: 24f6cd72352c4201df22a5be356d4d22

// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "LinkedList",
    products: [
        .library(name: "LinkedList", targets: ["LinkedList"])
    ],
    targets: [
        .target(name: "LinkedList"),
        .testTarget(name: "LinkedListTests", dependencies: ["LinkedList"]),
    ],
    swiftLanguageVersions: [.v3, .v4]
)
```

Otherwise,
the server SHOULD respond with a status code of `303` (See Other)
and redirect to the unqualified `Package.swift` resource.

```http
HTTP/1.1 303 See Other
Content-Version: 1
Location: https://packages.example.com/github.com/mona/LinkedList/1.1.1/Package.swift
```

<a name="endpoint-4"></a>

### 4.4. Fetch source archive

A client MAY send a `GET` request
for a URI matching the expression `/{package}/{version}`
to retrieve a release's source archive.
A client SHOULD set the `Accept` header to
`application/vnd.swift.registry.v1+zip`
and SHOULD append the `.zip` extension to the requested URI.

```http
GET /github.com/mona/LinkedList/1.1.1.zip HTTP/1.1
Host: packages.example.com
Accept: application/vnd.swift.registry.v1+zip
```

If a release is found for the requested URI,
a server SHOULD respond with a status code of `200` (OK)
and the `Content-Type` header `application/zip`.
Otherwise, a server SHOULD respond with a status code of `404` (NOT FOUND).

```http
HTTP/1.1 200 OK
Accept-Ranges: bytes
Cache-Control: public, immutable
Content-Type: application/zip
Content-Disposition: attachment; filename="LinkedList-1.1.1.zip"
Content-Length: 2048
Content-Version: 1
Digest: sha-256=a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812
ETag: e61befdd5056d4b8bafa71c5bbb41d71
Link: <https://mirror-japanwest.example.com/mona-LinkedList-1.1.1.zip>; rel=duplicate; geo=jp; pri=10; type="application/zip"
```

A server SHALL respond with a `Content-Length` header
set to the size of the archive in bytes.
A client SHOULD terminate requests whose responses exceed
the expected content length.

A server SHALL respond with a `Digest` header
containing a SHA-256 checksum for the source archive.

A server SHOULD respond with a `Content-Disposition` header
set to `attachment` with a `filename` parameter equal to the name of the package
followed by a hyphen (`-`), the version number, and file extension
(for example, "LinkedList-1.1.1.zip").

It is RECOMMENDED for clients and servers to support
range requests as described by [RFC 7233]
and caching as described by [RFC 7234].

#### 4.4.1. Integrity verification

A client SHOULD verify the integrity of a downloaded source archive
using the checksum provided in the `Digest` header of a response
(for example, using the command
`echo "$CHECKSUM LinkedList-1.1.1.zip" | shasum -a 256 -c`).

#### 4.4.2. Download locations

A server MAY specify mirrors or multiple download locations
using `Link` header fields
with a `duplicate` relation,
as described by [RFC 6249].
A client MAY use this information
to determine its preferred strategy for downloading.

A server that indexes but doesn't host packages
SHOULD respond with a status code of `303` (See Other)
and redirect to a hosted package archive if one is available.

```http
HTTP/1.1 303 See Other
Content-Version: 1
Location: https://packages.example.com/github.com/mona/LinkedList/1.1.1.zip
```

## 5. Normative References

* [RFC 2119]: Key words for use in RFCs to Indicate Requirement Levels
* [RFC 3230]: Instance Digests in HTTP
* [RFC 3986]: Uniform Resource Identifier (URI): Generic Syntax
* [RFC 3987]: Internationalized Resource Identifiers (IRIs)
* [RFC 5234]: Augmented BNF for Syntax Specifications: ABNF
* [RFC 5843]: Additional Hash Algorithms for HTTP Instance Digests
* [RFC 6249]: Metalink/HTTP: Mirrors and Hashes
* [RFC 6570]: URI Template
* [RFC 7230]: Hypertext Transfer Protocol (HTTP/1.1): Message Syntax and Routing
* [RFC 7231]: Hypertext Transfer Protocol (HTTP/1.1): Semantics and Content
* [RFC 7233]: Hypertext Transfer Protocol (HTTP/1.1): Range Requests
* [RFC 7234]: Hypertext Transfer Protocol (HTTP/1.1): Caching
* [RFC 7807]: Problem Details for HTTP APIs
* [RFC 8288]: Web Linking
* [SemVer]: Semantic Versioning

## 6. Informative References

* [BCP 13] Media Type Specifications and Registration Procedures
* [RFC 6749]: The OAuth 2.0 Authorization Framework
* [RFC 8446]: The Transport Layer Security (TLS) Protocol Version 1.3
* [TR36]: Unicode Technical Report #36: Unicode Security Considerations
* [JSON-LD]: A JSON-based Serialization for Linked Data
* [Schema.org] A shared vocabulary for structured data.

[BCP 13]: https://tools.ietf.org/html/rfc6838 "Media Type Specifications and Registration Procedures"
[RFC 2119]: https://tools.ietf.org/html/rfc2119 "Key words for use in RFCs to Indicate Requirement Levels"
[RFC 3230]: https://tools.ietf.org/html/rfc5843 "Instance Digests in HTTP"
[RFC 3986]: https://tools.ietf.org/html/rfc3986 "Uniform Resource Identifier (URI): Generic Syntax"
[RFC 3987]: https://tools.ietf.org/html/rfc3987 "Internationalized Resource Identifiers (IRIs)"
[RFC 5234]: https://tools.ietf.org/html/rfc5234 "Augmented BNF for Syntax Specifications: ABNF"
[RFC 5843]: https://tools.ietf.org/html/rfc5843 "Additional Hash Algorithms for HTTP Instance Digests"
[RFC 6249]: https://tools.ietf.org/html/rfc6249 "Metalink/HTTP: Mirrors and Hashes"
[RFC 6570]: https://tools.ietf.org/html/rfc6570 "URI Template"
[RFC 6749]: https://tools.ietf.org/html/rfc6749 "The OAuth 2.0 Authorization Framework"
[RFC 7230]: https://tools.ietf.org/html/rfc7230 "Hypertext Transfer Protocol (HTTP/1.1): Message Syntax and Routing"
[RFC 7231]: https://tools.ietf.org/html/rfc7231 "Hypertext Transfer Protocol (HTTP/1.1): Semantics and Content"
[RFC 7233]: https://tools.ietf.org/html/rfc7233 "Hypertext Transfer Protocol (HTTP/1.1): Range Requests"
[RFC 7234]: https://tools.ietf.org/html/rfc7234 "Hypertext Transfer Protocol (HTTP/1.1): Caching"
[RFC 7807]: https://tools.ietf.org/html/rfc7807 "Problem Details for HTTP APIs"
[RFC 8288]: https://tools.ietf.org/html/rfc8288 "Web Linking"
[RFC 8446]: https://tools.ietf.org/html/rfc8446 "The Transport Layer Security (TLS) Protocol Version 1.3"
[TR36]: http://www.unicode.org/reports/tr36/ "Unicode Technical Report #36: Unicode Security Considerations"
[IANA Link Relations]: https://www.iana.org/assignments/link-relations/link-relations.xhtml
[JSON-LD]: https://w3c.github.io/json-ld-syntax/ "JSON-LD 1.1: A JSON-based Serialization for Linked Data"
[SemVer]: https://semver.org/ "Semantic Versioning"
[Schema.org]: https://schema.org/
[SoftwareSourceCode]: https://schema.org/SoftwareSourceCode
[DUST]: https://doi.org/10.1145/1462148.1462151 "Bar-Yossef, Ziv, et al. Do Not Crawl in the DUST: Different URLs with Similar Text. Association for Computing Machinery, 17 Jan. 2009. January 2009"

[GitHub / Swift Package Management Service]: https://forums.swift.org/t/github-swift-package-management-service/30406

[RubyGems]: https://rubygems.org "RubyGems: The Ruby community’s gem hosting service"
[PyPI]: https://pypi.org "PyPI: The Python Package Index"
[npm]: https://www.npmjs.com "The npm Registry"
[crates.io]: https://crates.io "crates.io: The Rust community’s crate registry"
[CocoaPods]: https://cocoapods.org "A dependency manager for Swift and Objective-C Cocoa projects"
[thundering herd effect]: https://en.wikipedia.org/wiki/Thundering_herd_problem "Thundering herd problem"
[offline cache]: https://yarnpkg.com/features/offline-cache "Offline Cache | Yarn - Package Manager"
[XCFramework]: https://developer.apple.com/videos/play/wwdc2019/416/ "WWDC 2019 Session 416: Binary Frameworks in Swift"
[SE-0272]: https://github.com/apple/swift-evolution/blob/master/proposals/0272-swiftpm-binary-dependencies.md "Package Manager Binary Dependencies"
