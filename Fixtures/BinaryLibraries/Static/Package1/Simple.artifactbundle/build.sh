#!/bin/bash

# currently only used for Windows

rm -fr .build
swift build --arch arm64 -c release
swift build --arch x86_64 -c release

cd dist
rm -fr windows
mkdir windows
cd windows
cp ../../.build/arm64-unknown-windows-msvc/release/libSimple.a Simple_arm64.lib
cp ../../.build/x86_64-unknown-windows-msvc/release/libSimple.a Simple_x86_64.lib
