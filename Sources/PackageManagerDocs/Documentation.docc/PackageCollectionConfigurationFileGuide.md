# Configuration file

Learn about how package collections are configured.

## Overview

Configuration that pertains to package collections are stored in the file `~/.swiftpm/config/collections.json`. It keeps track of user's list of configured collections
and preferences such as those set by the `--trust-unsigned` and `--skip-signature-check` flags in the [`package-collection add` command](#add-subcommand). 

This file is managed through SwiftPM commands and users are not expected to edit it by hand.

