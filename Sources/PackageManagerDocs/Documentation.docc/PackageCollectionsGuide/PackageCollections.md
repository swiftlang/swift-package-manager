# Package Collections

Learn to create and use Swift package collections.

## Overview

Package collections, introduced by [SE-0291](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0291-package-collections.md), are
curated lists of packages and associated metadata that can be imported
by SwiftPM to make discovery of existing packages easier. 
They are authored as static JSON documents 
and can be published to the web or distributed to local file systems. 

Educators and community influencers can publish
package collections to go along with course materials or blog posts, removing the friction of using
packages for the first time and the cognitive overload of deciding which packages are useful for
a particular task. 
Enterprises may use collections to narrow the decision space for their internal
engineering teams, focusing them on a trusted set of vetted packages.

## Using the package-collection CLI

With the `swift package-collection` command-line interface, SwiftPM users can subscribe to package collections. 
Contents of imported package 
collections are accessible to any clients of [libSwiftPM](libSwiftPM.md). <!-- TODO: to link to libSwiftPM article when available. -->

`swift package-collection` has the following subcommands:
- [`add`](<doc:PackageCollectionAdd>): Add a new collection
- [`describe`](<doc:PackageCollectionDescribe>): Get metadata for a collection or a package included in an imported collection
- [`list`](<doc:PackageCollectionList>): List configured collections
- [`refresh`](<doc:PackageCollectionRefresh>): Refresh configured collections
- [`remove`](<doc:PackageCollectionRemove>): Remove a configured collection
- [`search`](<doc:PackageCollectionSearch>): Search for packages by keywords or module names within imported collections

## Topics

### Getting Started
- <doc:PackageCollectionCreationGuide>
- <doc:PackageCollectionSigning>

### Modifying Package Collections 
- <doc:PackageCollectionAddGuide>
- <doc:PackageCollectionRemoveGuide>
- <doc:PackageCollectionRefreshGuide>

### Inspecting Package Collections
- <doc:PackageCollectionSearchGuide>
- <doc:PackageCollectionListGuide>
- <doc:PackageCollectionDescribeGuide>

