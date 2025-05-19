# Swift package example that uses system library dependency without pkg-config

Create an Command-line executable package that uses jpeg as a system library dependency.

## Overview

The follow example uses [IJG’s JPEG library](http://www.ijg.org) from an executable, which has some caveats.
Most notably, when installed using Homebrew, the library does not include a pkg-config file, and the header it provides isn't directly usable as a Swift module.

### Set up the package

Create a directory called `example`, and initialize it as a package that builds
an executable:

```bash
$ mkdir example
$ cd example
example$ swift package init --type executable
```

Edit the `Sources/main.swift` so it consists of this code:

```swift
import CJPEG

let jpegData = jpeg_common_struct()
print(jpegData)
```

### Install the JPEG library

On macOS you can use Homebrew package manager: `brew install jpeg`.
`jpeg` is a keg-only formula, meaning it won't be linked to `/usr/local/lib`, and you'll have to link it manually at build time.

Just like in the previous example, run `mkdir Sources/CJPEG` and add the following `module.modulemap`:

```
module CJPEG [system] {
    header "shim.h"
    header "/opt/homebrew/opt/jpeg/include/jpeglib.h"
    link "jpeg"
    export *
}
```

### Add a shim header

Create a `shim.h` file in the same directory and add `#include <stdio.h>` in
it.

```bash
$ echo '#include <stdio.h>' > shim.h
```

The shim is required  because `jpeglib.h` doesn't contain the required line `#include <stdio.h>`, required for a Swift module.
Alternatively, you can add `#include <stdio.h>` to the top of jpeglib.h to avoid creating the `shim.h` file.

### Add a system library target

Now to use the CJPEG package, declare our dependency in our example app’s `Package.swift`:

```swift

import PackageDescription

let package = Package(
    name: "example",
    targets: [
        .executableTarget(
            name: "example",
            dependencies: ["CJPEG"],
            path: "Sources"
            ),
        .systemLibrary(
            name: "CJPEG",
            providers: [
                .brew(["jpeg"])
            ])
    ]
)
```

### Build the package

To use `swift build` to build out example, specify the location of the `jpeg` library:

```bash
example% swift build -Xlinker -L/opt/homebrew/opt/jpeg/lib
```

You have to specify the path where the libjpeg is present using `-Xlinker` because there is no pkg-config file for it. 

> Warning: the above steps don't work if you installed JPEG with [Homebrew](http://brew.sh) on an Intel mac.
> Homebrew installs files to `/usr/local` on Macs with Intel processors, or `/opt/homebrew` on a Mac with Apple silicon. 
> Adopt the paths appropriately for your situation.

### Run the built executable

To invoke the executable you built, run the command:

```bash
example$ .build/debug/example
jpeg_common_struct(err: nil, mem: nil, progress: nil, client_data: nil, is_decompressor: 0, global_state: 0)
```
