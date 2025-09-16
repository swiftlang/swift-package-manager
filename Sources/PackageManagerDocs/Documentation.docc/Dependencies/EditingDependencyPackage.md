# Editing a remote dependency used in a Swift package

Temporarily switch a remote dependency to local in order to edit the dependency.

## Overview

Swift package manager supports editing dependencies, when your work requires making a change to one of your dependencies (for example, to fix a bug, or add a new API).
The package manager moves the dependency into a location under the `Packages/` directory where it can be edited.

For the packages which are in the editable state, `swift build` uses the exact sources in this directory to build, regardless of their state, Git repository status, tags, or the tag desired by dependency resolution.
In other words, this _just builds_ against the sources that are present.
When an editable package is present, it is used to satisfy all instances of that package in the dependency graph.
It is possible to edit all, some, or none of the packages in a dependency graph, without restriction.

Editable packages are best used to do experimentation with dependency code, or to create and submit a patch in the dependency owner's repository (upstream).
There are two ways to put a package in editable state, using <doc:PackageEdit>.
The first example creates a branch called `bugFix` from the currently resolved version and puts the dependency `PlayingCard` in the `Packages/` directory:

```bash
$ swift package edit PlayingCard --branch bugFix
```

The second is similar, except that the Package Manager leaves the dependency at a detached HEAD at the commit you specified.

```bash
$ swift package edit PlayingCard --revision 969c6a9
```

> Note: If the branch or revision option is not provided, the Package Manager uses the currently resolved version on a detached HEAD.

Once a package is in an editable state, you can navigate to the directory `Packages/PlayingCard` to make changes, build and then push the changes or open a pull request to the upstream repository.

You can end editing a package with <doc:PackageUnedit>.


```bash
$ swift package unedit PlayingCard
```

This removes the edited dependency from `Packages/` and restores the originally resolved version.

This command fails if you have uncommitted changes or changes which are not pushed to the remote repository.
If you want to discard these changes and unedit, use the `--force` option:

```bash
$ swift package unedit PlayingCard --force
```

### Top of Tree Development

This feature allows overriding a dependency with a local checkout on the filesystem.
This checkout is completely unmanaged by the package manager and is used as-is.
The only requirement is that the package name in the overridden checkout shouldn't change.
This is useful when developing multiple packages in tandem, or when working on packages alongside an
application.

The command to attach (or create) a local checkout is:

```bash
$ swift package edit <package name> \
    --path <path/to/dependency>
```

For example, if `PlayingCard` depends on `swift-collections` and you have a checkout of `swift-collections` at
`/workspace/swift-collections`:

```bash
$ swift package edit swift-collections \
    --path /workspace/swift-collections
```

A checkout of `swift-collections` is created if it doesn't exist at the path you specified.
If a checkout exists, package manager validates the package name at the given path and attaches to it.

The package manager also creates a symlink in the `Packages/` directory to the checkout path.

Use <doc:PackageUnedit> command to stop using the local checkout:

```bash
$ swift package unedit swift-collections
```
