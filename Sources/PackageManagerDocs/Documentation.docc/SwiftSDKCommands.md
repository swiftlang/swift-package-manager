# swift sdk

Perform operations on Swift SDKs.

@Metadata {
    @PageImage(purpose: icon, source: command-icon)
    @Available("Swift", introduced: "6.1")
}

## Overview

By default, Swift Package Manager compiles code for the host platform on which you run it.
Swift 6.1 introduced SDKs (through
[SE-0387](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md))
to support cross-compilation.

SDKs are tightly coupled with the toolchain used to create them.
Supported SDKs are distributed by the Swift project with links on the [installation page](https://www.swift.org/install/) for macOS and Linux, and included in the distribution for Windows.

Additionally, the Swift project provides the tooling repository [swift-sdk-generator](https://github.com/swiftlang/swift-sdk-generator) that you can use to create a custom SDK for your preferred platform.

## Topics 

### Installing an SDK
- <doc:SDKInstall>

### Listing SDKs
- <doc:SDKList>

### Removing an SDK
- <doc:SDKRemove>

### Configuring an SDK
- <doc:SDKConfigure>

### Deprecated Commands
- <doc:SDKConfigurationSet>
- <doc:SDKConfigurationShow>
- <doc:SDKConfigurationReset>

