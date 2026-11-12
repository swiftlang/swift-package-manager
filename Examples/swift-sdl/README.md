# Swift SDL Example

This is a living example of building a cross-platform application using the SDL library with a Swift package. The goal is to make this package as clean as possible showing of the improved ergonomics.

This is the first version which shows off the host prebuilts features with a macro and a generator build tool that uses swift-syntax and fully uses the prebuilts. Previously it was just limited to macros.

## Setup

To set up you need to checkout the SDL library from https://github.com/libsdl-org/SDL into the root folder of this package.

You then need to perform a CMake build by hand for the platform you are targeting. This produces a static library and for Android the SDL.jar file for the Java bridge.

### MacOS

```
cmake -G Ninja -B build-macos -S . -DSDL_STATIC=ON -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0
cmake --build build-macos --target SDL3-static
```

Then simply do a `swift run MyAppExe` to run the sample app.

Or you can open the MyXcodeApp project in Xcode and run MyXcodeApp on your Mac.

### Android

Requires the ANDROID_HOME and ANDROID_NDK_HOME environment variables to be set. Currently we’re only building the MyAppCore library until we get custom target support for the APK build.

```
cmake -G Ninja -B build-android -S . --toolchain ../android.toolchain -DSDL_STATIC=ON -DSDL_ANDROID_HOME=$ANDROID_HOME
JDK_JAVAC_OPTIONS="--release 17" cmake --build build-android --target SDL3-static SDL3-jar
```

To build the native library that can be used by an Android app, install the 6.4.2 version of the Android SDK and use the matching 6.4.2 toolchain to build.

```
swift build --swift-sdk swift-6.4.2-RELEASE_android --triple aarch64-unknown-linux-android35 --product MyAppAndroid
```

### iOS Simulator

The MyXcodeApp project also supports the iOS Simulator to build SDL3 for the simulator:

```
cmake -G Ninja -B build-ios -S . -DSDL_STATIC=ON -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator
cmake --build build-ios --target SDL3-static
```

You can then run MyXcodeApp on any of the iPhone simulators.
