# Appendix B - Package Release Metadata JSON Schema

JSON schema for the `metadata` object accepted by a create package release request.

The `metadata` section of the [create package release request](<doc:RegistryServerSpecification#4.6.-Create-a-package-release>)
must be a JSON object of type [`PackageRelease`](<doc:#PackageRelease-type>), as defined in the
JSON schema below.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md",
  "title": "Package Release Metadata",
  "description": "Metadata of a package release.",
  "type": "object",
  "properties": {
    "author": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name of the author."
        },
        "email": {
          "type": "string",
          "format": "email",
          "description": "Email address of the author."
        },
        "description": {
          "type": "string",
          "description": "A description of the author."
        },
        "organization": {
          "type": "object",
          "properties": {
            "name": {
              "type": "string",
              "description": "Name of the organization."
            },
            "email": {
              "type": "string",
              "format": "email",
              "description": "Email address of the organization."
            },
            "description": {
              "type": "string",
              "description": "A description of the organization."
            },
            "url": {
              "type": "string",
              "format": "uri",
              "description": "URL of the organization."
            },
          },
          "required": ["name"]
        },
        "url": {
          "type": "string",
          "format": "uri",
          "description": "URL of the author."
        },
      },
      "required": ["name"]
    },
    "description": {
      "type": "string",
      "description": "A description of the package release."
    },
    "licenseURL": {
      "type": "string",
      "format": "uri",
      "description": "URL of the package release's license document."
    },
    "originalPublicationTime": {
      "type": "string",
      "format": "date-time",
      "description": "Original publication time of the package release in ISO 8601 format."
    },
    "readmeURL": {
      "type": "string",
      "format": "uri",
      "description": "URL of the README specifically for the package release or broadly for the package."
    },
    "repositoryURLs": {
      "type": "array",
      "description": "Code repository URL(s) of the package release.",
      "items": {
        "type": "string",
        "description": "Code repository URL."
      }
    }
  }
}
```

###### PackageRelease type

| Property                  | Type                | Description                                      | Required |
| ------------------------- | :-----------------: | ------------------------------------------------ | :------: |
| `author`                  | [Author](<doc:#Author-type>) | Author of the package release. | |
| `description`             | String | A description of the package release. | |
| `licenseURL`              | String | URL of the package release's license document. | |
| `originalPublicationTime` | String | Original publication time of the package release in [ISO 8601] format. This can be set if the package release was previously published elsewhere.<br>A registry should record the publication time independently and include it as `publishedAt` in the [package release metadata response](<doc:RegistryServerSpecification#4.2.-Fetch-information-about-a-package-release>). <br>In case both `originalPublicationTime` and `publishedAt` are set, `originalPublicationTime` should be used. | |
| `readmeURL`       | String | URL of the README specifically for the package release or broadly for the package. | |
| `repositoryURLs`  | Array | Code repository URL(s) of the package. It is recommended to include all URL variations (e.g., SSH, HTTPS) for the same repository. This can be an empty array if the package does not have source control representation.<br/>Setting this property is one way through which a registry can obtain repository URL to package identifier mappings for the ["lookup package identifiers registered for a URL" API](<doc:RegistryServerSpecification#4.5.-Lookup-package-identifiers-registered-for-a-URL>). A registry may choose other mechanism(s) for package authors to specify such mappings. | |

###### Author type

| Property          | Type                | Description                                      | Required |
| ----------------- | :-----------------: | ------------------------------------------------ | :------: |
| `name`            | String | Name of the author. | ✓ |
| `email`           | String | Email address of the author. | |
| `description`     | String | A description of the author. | |
| `organization`    | [Organization](<doc:#Organization-type>) | Organization that the author belongs to. | |
| `url`             | String | URL of the author. | |

###### Organization type

| Property          | Type                | Description                                      | Required |
| ----------------- | :-----------------: | ------------------------------------------------ | :------: |
| `name`            | String | Name of the organization. | ✓ |
| `email`           | String | Email address of the organization. | |
| `description`     | String | A description of the organization. | |
| `url`             | String | URL of the organization. | |

[ISO 8601]: https://www.iso.org/iso-8601-date-and-time-format.html "ISO 8601 Date and Time Format"
