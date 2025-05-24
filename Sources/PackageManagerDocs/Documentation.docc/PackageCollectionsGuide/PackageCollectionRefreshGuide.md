# Refreshing package collection data

Refresh the cached data for package collections.

## Overview

The [`refresh` subcommand](<doc:PackageCollectionRefresh>) refreshes any cached data manually:

```bash
$ swift package-collection refresh
Refreshed 5 configured package collections.
```

SwiftPM will also automatically refresh data under various conditions, but some queries such as search will rely on locally cached data.

