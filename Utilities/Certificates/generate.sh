#!/bin/sh

swift build
cp .build/arm64-apple-macosx/debug/Certificates.build/DerivedSources/embedded_resources.swift ../../Sources/PackageSigning/
