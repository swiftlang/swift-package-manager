# Editing a Swift package

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

Swift package manager supports editing dependencies, when your work requires
making a change to one of your dependencies (for example, to fix a bug, or add
a new API). The package manager moves the dependency into a location under the
`Packages/` directory where it can be edited.

For the packages which are in the editable state, `swift build` will always use
the exact sources in this directory to build, regardless of their state, Git
repository status, tags, or the tag desired by dependency resolution. In other
words, this will _just build_ against the sources that are present. When an
editable package is present, it will be used to satisfy all instances of that
package in the dependency graph. It is possible to edit all, some, or none of
the packages in a dependency graph, without restriction.

Editable packages are best used to do experimentation with dependency code, or to
create and submit a patch in the dependency owner's repository (upstream).
There are two ways to put a package in editable state:

    $ swift package edit Foo --branch bugFix

This will create a branch called `bugFix` from the currently resolved version and
put the dependency `Foo` in the `Packages/` directory.

    $ swift package edit Foo --revision 969c6a9

This is similar to the previous version, except that the Package Manager will leave
the dependency at a detached HEAD on the specified revision.

Note: If the branch or revision option is not provided, the Package Manager will
checkout the currently resolved version on a detached HEAD.

Once a package is in an editable state, you can navigate to the directory
`Packages/Foo` to make changes, build and then push the changes or open a pull
request to the upstream repository.

You can end editing a package using `unedit` command:

    $ swift package unedit Foo

This will remove the edited dependency from `Packages/` and put the originally
resolved version back.

This command fails if there are uncommitted changes or changes which are not
pushed to the remote repository. If you want to discard these changes and
unedit, you can use the `--force` option:

    $ swift package unedit Foo --force

### Top of Tree Development

This feature allows overriding a dependency with a local checkout on the
filesystem. This checkout is completely unmanaged by the package manager and
will be used as-is. The only requirement is that the package name in the
overridden checkout should not change. This is extremely useful when developing
multiple packages in tandem or when working on packages alongside an
application.

The command to attach (or create) a local checkout is:

    $ swift package edit <package name> --path <path/to/dependency>

For example, if `Foo` depends on `Bar` and you have a checkout of `Bar` at
`/workspace/bar`:

    foo$ swift package edit Bar --path /workspace/bar

A checkout of `Bar` will be created if it doesn't exist at the given path. If
a checkout exists, package manager will validate the package name at the given
path and attach to it.

The package manager will also create a symlink in the `Packages/` directory to the
checkout path.

Use unedit command to stop using the local checkout:

    $ swift package unedit <package name>
    # Example:
    $ swift package unedit Bar
