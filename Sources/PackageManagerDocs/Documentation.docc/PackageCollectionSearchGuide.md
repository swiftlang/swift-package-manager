# Searching for a package

## Overview

The [`search` subcommand](<doc:PackageCollectionSearch>) searches for packages by keywords or module names within imported collections. The result can optionally be returned as JSON using `--json` for
integration into other tools.

### String-based search

The search command does a string-based search when using the `--keywords` option and returns the list of packages that matches the query:

```bash
$ swift package-collection search [--json] --keywords yaml
https://github.com/jpsim/yams: A sweet and swifty YAML parser built on LibYAML.
...
```

### Module-based search

The search command does a search for a specific module name when using the `--module` option:

```bash
$ swift package-collection search [--json] --module yams
Package Name: Yams
Latest Version: 4.0.0
Description: A sweet and swifty YAML parser built on LibYAML.
--------------------------------------------------------------
...
```

