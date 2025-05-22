# Listing configured Package Collections

Discover user-configured Package Collections.

## Overview

List [`list` subcommand](<doc:PackageCollectionList>) lists all collections that are configured by the user:

```bash
$ swift package-collection list [--json]
Sample Package Collection - https://example.com/packages.json
...
```

The result can optionally be returned as JSON using `--json` for integration into other tools.
