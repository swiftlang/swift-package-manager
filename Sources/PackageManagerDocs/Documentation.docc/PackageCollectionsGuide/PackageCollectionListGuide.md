# List existing package collections

Discover user-configured package collections.

## Overview

List [`list` subcommand](<doc:PackageCollectionList>) lists all collections that are configured by the user:

```bash
$ swift package-collection list [--json]
Sample Package Collection - https://example.com/packages.json
...
```

The result can optionally be returned as JSON using `--json` for integration into other tools.
