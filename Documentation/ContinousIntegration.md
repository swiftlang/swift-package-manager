# Building Swift Packages or Apps that Use Them in Continuous Integration Workflows

Build Swift packages with an existing continuous integration setup and prepare apps that consume package dependencies within an existing CI pipeline.

## Overview

*Continuous integration* (*CI*) is the process of automating and streamlining the building, analyzing, testing, archiving, and publishing of your apps to ensure that they're always in a releasable state.
Most projects that contain or depend on Swift packages don't require additional configuration.

## Use the Expected Version of a Package Dependency

To ensure the *CI* workflow’s reliability, make sure it uses the appropriate version of package dependencies.
SwiftPM records the result of dependency resolution in `Package.resolved` (at the top-level of the package) and it's used when performing dependency resolution (rather than having SwiftPM searching the latest eligible version of each package).  Running `swift package update` updates all dependencies to the latest eligible versions and updates the `Package.resolved`.  You can commit `Package.resolved` to your *Git* repository to ensure it’s always up-to-date on the *CI* environment to prevent the *CI* from building your project with unexpected versions of package dependencies.  Otherwise you can choose to add `Package.resolved` file to `.gitignore` file and have `swift package resolve` command in charge of resolving the dependencies (`swift package resolve` is invoked by most SwiftPM commands).

## Provide Credentials

To resolve package dependencies that require authentication, or private packages, you need to provide credentials to your CI setup.

* Use the SSH–based Git URL for your packages URL:
```
dependencies: [
  .package(url: "git@github.com:{username}/{packageRepository}.git"),
  .package(url: "git@github.com:{username}/{package2Repository}.git")
]
```
* Create a `.ssh` directory into the root folder of your package (at the same level of Package.swift file).
* Inside the `.ssh` directory, generate a new SSH key:
```
ssh-keygen -b 4096 -t rsa -N "" -f {keyName}
```
* Inside the `.ssh` directory, add a file called `config` and add to it:
```
Host github.com
  HostName github.com
  User {yourGithubEmail}
  IdentityFile ./.ssh/{keyName}
```
* Copy the SSH key to your clipboard:
```
pbcopy < {keyName}.pub
```
* Add the copied in your Github Account Settings.
