##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2025 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

param (
    [switch]$SkipAndroid,
    [switch]$InstallCMake
)

# winget isn't easily made available in containers, so use chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

if ($InstallCMake) {
    choco install -y cmake --installargs 'ADD_CMAKE_TO_PATH=System' --apply-install-arguments-to-dependencies
    choco install -y ninja

    Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
    refreshenv

    # Let swiftc find the path to link.exe in the CMake smoke test
    $env:Path += ";$(Split-Path -Path "$(& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" "-latest" -products Microsoft.VisualStudio.Product.BuildTools -find VC\Tools\MSVC\*\bin\HostX64\x64\link.exe)" -Parent)"
}

if (-not $SkipAndroid) {
    choco install -y android-ndk

    Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
    refreshenv

    # Work around a bug in the package causing the env var to be set incorrectly
    $env:ANDROID_NDK_ROOT = $env:ANDROID_NDK_ROOT.replace('-windows.zip','')
}
