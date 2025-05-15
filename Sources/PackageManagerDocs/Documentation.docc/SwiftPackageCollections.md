# Package Collections

Learn to create and use Swift package collections.

## Overview

Package collections, introduced by [SE-0291](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0291-package-collections.md), are
curated lists of packages and associated metadata that make discovery of existing packages easier. 
They are authored as static JSON documents 
and can be published to the web or distributed to local file systems. 

## Using package collections

With the `swift package-collection` command-line interface, SwiftPM users can subscribe to package collections. Contents of imported package 
collections are accessible to any clients of [libSwiftPM](libSwiftPM.md).

`swift package-collection` has the following subcommands:
- [`add`](<doc:PackageCollectionAdd>): Add a new collection
- [`describe`](#describe-subcommand): Get metadata for a collection or a package included in an imported collection
- [`list`](#list-subcommand): List configured collections
- [`refresh`](#refresh-subcommand): Refresh configured collections
- [`remove`](#remove-subcommand): Remove a configured collection
- [`search`](#search-subcommand): Search for packages by keywords or module names within imported collections

## Topics

- [`Signed Package Collections`](<doc:PackageCollectionSigned>)
- [`Unsigned package collections`](<doc:PackageCollectionsUnsigned>)
