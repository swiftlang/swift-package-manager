# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

target_sources(PackageModel PUBLIC
  FilteredDependencyDescription.swift
  PackageConditionDescription.swift
  PackageDependencyDescription.swift
  PlatformDescription.swift
  ProductDescription.swift
  SystemPackageProviderDescription.swift
  TargetBuildSettingDescription.swift
  TargetDescription.swift)
