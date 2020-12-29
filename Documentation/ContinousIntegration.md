# Building Swift Packages or Apps that Use Them in Continuous Integration Workflows

Build Swift packages with an existing continuous integration setup and prepare apps that consume package dependencies within an existing CI pipeline.

## Overview

*Continuous integration* (*CI*) is the process of automating and streamlining the building, analyzing, testing, archiving, and publishing of your apps to ensure that they're always in a releasable state.
Most projects that contain or depend on Swift packages don't require additional configuration. However, be sure to commit your project's Package.resolved file to your *Git* repository to ensure a reliable *CI* workflow that always uses the expected version of a package dependency.
If your project depends on packages that require authentication you may need to perform additional configuration.

## Use the Expected Version of a Package Dependency

To ensure the *CI* workflow’s reliability, make sure it uses the appropriate version of package dependencies.
Update each package dependency in `Package.resolved` and commit it to your *Git* repository to ensure it’s always up-to-date on the *CI* environment to prevent the *CI* from building your project with unexpected versions of package dependencies.

## Provide Credentials

To resolve package dependencies that require authentication, or private packages, you need to provide credentials to your CI setup.
