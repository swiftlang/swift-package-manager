# Continuous Integration Workflows

Build Swift packages with an existing continuous integration setup and prepare apps that consume package dependencies within an existing CI pipeline.

## Overview

*Continuous integration* (*CI*) is the process of automating and streamlining the building, analyzing, testing, archiving, and publishing of your apps to ensure that they're always in a releasable state.
Most projects that contain or depend on Swift packages don't require additional configuration.

## Use the Expected Version of a Package Dependency

To ensure a CI workflow’s reliability, verify it uses the appropriate version of package dependencies.
SwiftPM records the result of dependency resolution in the file `Package.resolved`, at the top-level of the package.
When available, it's used when performing dependency resolution.

Run <doc:PackageUpdate> to update dependencies to the latest eligible versions and update `Package.resolved`.
For more information on resolving and updating dependencies, see <doc:ResolvingPackageVersions>.


## Provide Credentials

To resolve package dependencies that require authentication, such as private packages, provide credentials to your CI setup.
Package manager honors the machine's SSH configuration - there's no additional setup required.
For private package, use the SSH-based Git URLs and configure SSH credentials.
You may also need to set up a `known_hosts` file in the `~/.ssh` directory of the user that runs your CI tasks.

CI services like [Jenkins](https://www.jenkins.io/doc/book/using/using-credentials), [Github Action](https://docs.github.com/en/free-pro-team@latest/actions/reference/authentication-in-a-workflow), [TravisCI](https://docs.travis-ci.com/user/private-dependencies), and [CircleCI](https://circleci.com/docs/2.0/gh-bb-integration/#security) provide ways to set up SSH keys or other techniques to access private repositories.
Since Package manager uses git to clone the repositories there's no additional setup required; Package manager honors the machine's SSH and Git configuration.

## Using xcodebuild

When building on macOS based CI hosts you can use the command-line tool `xcodebuild`.
`xcodebuild` uses Xcode's built-in Git tooling to connect to repositories.

In many cases, you don't need to make changes to how xcodebuild connects to them.
However, some use cases require you use the git configuration — for example URL remapping, the use of proxies, or advanced SSH configurations.
To have xcodebuild use your Mac's Git installation and configuration instead of Xcode's built-in Git tooling, pass `-scmProvider system` to the xcodebuild command.

For more information on using xcodebuild in continuous integration workflows, visit [Building Swift packages or apps that use them in continuous integration workflows](https://developer.apple.com/documentation/swift_packages/building_swift_packages_or_apps_that_use_them_in_continuous_integration_workflows).
