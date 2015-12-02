# System Modules

You can link against system libraries using the package manager.

To do so special packages must be published that contain a module map for that library.

Let’s use the example of [IJG’s JPEG library](http://www.ijg.org). This is the code we want to compile:

```swift
import CJPEG

let jpegData = jpeg_common_struct()
print(jpegData)
```

Lets put this code in a directory called `example`:

    $ mkdir example
    $ cd example
    example$ touch main.swift Package.swift
    example$ open -t main.swift Package.swift

To `import CJPEG` the package manager requires
that the JPEG library has been installed by a system packager (eg. `apt`, `brew`, `yum`, etc.).
The following files from the JPEG system-package are of interest:

    /usr/lib/libjpeg.so      # .dylib on OS X
    /usr/include/jpeglib.h

Swift packages that provide module maps for system libraries are handled differently from regular Swift packages.

Create a directory called `CJPEG` parallel to the `example` directory and create a file called `module.modulemap`:

    example$ cd ..
    $ mkdir CJPEG
    $ cd CJPEG
    CJPEG$ touch module.modulemap

Edit the `module.modulemap` so it consists of the following:

    module CJPEG [system] {
        header "/usr/include/jpeglib.h"
        link "jpeg"
        export *
    }

> The convention we hope the community will adopt is to prefix such modules with `C` and to camelcase the modules
> as per Swift module name conventions. Then the community is free to name another module simply `JPEG` which
> contains more “Swifty” function wrappers around the raw C interface.

Packages are Git repositories,
tagged with semantic versions
containing a `Package.swift` file at their root.
Thus we must create `Package.swift` and initialize a Git repository with at least one version tag:

    CJPEG$ touch Package.swift
    CJPEG$ git init
    CJPEG$ git add .
    CJPEG$ git ci -m "Initial Commit"
    CJPEG$ git tag 1.0.0

* * *

Now to consume JPEG we must declare our dependency in our example app’s `Package.swift`:

```swift
import PackageDescription

let package = Package(
    dependencies: [
        .Package(url: "../CJPEG", majorVersion: 1)
    ]
)
```

> Here we used a relative URL to speed up initial development. If (we hope when) you push
> your module map package to a public repository you must change the above URL reference
> so that it is a full, qualified git URL

Now if we type `swift build` in our example app directory we will create an executable:

    example$ swift build
    …
    example$ .build/debug/example
    jpeg_common_struct(err: 0x0000000000000000, mem: 0x0000000000000000, progress: 0x0000000000000000, client_data: 0x0000000000000000, is_decompressor: 0, global_state: 0)
    example$


## Module Maps With Dependencies

Let’s expand our example to include [JasPer](https://www.ece.uvic.ca/~frodo/jasper/), a JPEG-2000 library.
It depends on The JPEG Library.

First create a directory called `CJasPer` parallel to `CJPEG` and our example app:

    CJPEG$ cd ..
    $ mkdir CJasPer
    $ cd CJasPer
    CJasPer$ touch module.modulemap Package.swift

JasPer depends on JPEG thus any package that consumes `CJasPer` must know to also import `CJPEG`. We accomplish this by specifying the dependency in CJasPer’s `Package.swift`:

```swift
import PackageDescription

let package = Package(
    dependencies: [
        .Package(url: "../CJPEG", majorVersion: 1)
    ])
```

The module map for CJasPer is similar to that of CJPEG:

    module CJasPer [system] {
        header "/usr/local/include/jasper/jasper.h"
        link "jasper"
        export *
    }

**Take care**; the module map must specify all the headers that a system package uses,
***BUT*** you must not specify headers that are included
from the headers you have already specified.
For example with JasPer there are many headers
but all the others are included from the umbrella header `jasper.h`.
If you get the includes wrong you will get intermittent and hard to debug compile issues.

A package is a Git repository with semantically versioned tags and a `Package.swift` file, so we must create the Git repository:

    CJasPer$ git init
    CJasPer$ git add .
    CJasPer$ git ci -m "Initial Commit"
    CJasPer$ git tag 1.0.0

**PLEASE NOTE!** The package manager clones _the tag_. If you edit the `module.modulemap` and don’t `git tag -f 1.0.0` you will not build against your local changes.

* * *

Back in our example app’s `Package.swift` we can change our dependency to `CJasPer`:

```swift
import PackageDescription

let package = Package(
    dependencies: [
        .Package(url: "../CJasPer", majorVersion: 1)
    ])
```

CJasPer depends on CJPEG, so we do not need to specify our dependency on CJPEG in our example app’s Package.swift.

To test our JasPer support let’s amend our example’s `main.swift`:

```swift
import CJasPer

guard let version = String.fromCString(jas_getversion()) else {
    fatalError("Could not get JasPer version")
}

print("JasPer \(version)")
```

And run it:

    example$ swift build
    …
    example$ .build/debug/example
    JasPer 1.900.1
    example$


> Note we do not call the module `CLibjasper`. In general, avoid the lib prefix unless the authors of the package
> typically always refer to it that way. A good rule of thumb is to look at the header files, here we can
> see the header is called simply "jasper.h". In the event of non-typical headers (eg `jpeglib.h`) refer to the project homepage, the authors of the JPEG library refer to it as “The JPEG library” and not “libjpeg” or “jpeglib”. Pay attention to capitalization; it is `CJPEG` and not
> `CJpeg`, because JPEG is an acronym and is typically spelled all-caps.
> It is `CJasPer` and not `CJasper` because the project itself refers to the library as “JasPer” in all their documentation.

---

Please note that on Ubuntu 15.10 the above steps fail with:

    <module-includes>:1:10: note: in file included from <module-includes>:1:
    #include "/usr/include/jpeglib.h"
             ^
    /usr/include/jpeglib.h:792:3: error: unknown type name 'size_t'
      size_t free_in_buffer;        /* # of byte spaces remaining in buffer */
      ^

This is because `jpeglib.h` is not a correct module as bundled with Ubuntu (Homebrew’s jpeglib.h is correct however).
To fix this you need to add `#include <stdio.h>` to the top of jpeglib.h.

JPEG lib itself needs to be patched, but since this situation will be common we intend to add a workaround system in module packages.

## Packages That Provide Multiple Libraries

Some system packages provide multiple libraries (`.so` and `.dylib` files). In such cases you should add all the libraries to that Swift modulemap package’s `.modulemap` file:

    module CFoo [system] {
        header "/usr/local/include/foo/foo.h"
        link "foo"
        export *
    }
    
    module CFooBar [system] {
        header "/usr/include/foo/bar.h"
        link "foobar"
        export *
    }
    
    module CFooBaz [system] {
        header "/usr/include/foo/baz.h"
        link "foobaz"
        export *
    }

`foobar` and `foobaz` link to `foo`;
we don’t need to specify this information in the module-map because
the headers `foo/bar.h` and `foo/baz.h` both include `foo/foo.h`.
It is very important however that those headers do include their dependent headers,
otherwise when the modules are imported into Swift the dependent modules will not get
imported automatically and link errors will happen.
If these link errors occur to consumers of a package that consumes your
package the link errors can be especially difficult to debug.


## Cross-platform Module Maps

Module maps must contain absolute paths, thus they are not cross-platform. We intend to provide a solution for this in the package manager.

Long term we hope that system libraries and system packagers will provide module maps
and thus this component of the package manager will become redundant.

*Notably* the above steps will not work if you installed JPEG and JasPer with [Homebrew](http://brew.sh) since the files will
be installed to `/usr/local` for now adapt the paths, but as said, we plan to support basic relocations like these.


## Module Map Versioning

Version the module maps semantically.
The meaning of semantic version is less clear here, so use your best judgement.
Do not follow the version of the system library the module map represents,
version the module map(s) independently.

Follow the conventions of system packagers;
for example, the debian package for python3 is called python3,
as there is not a single package for python and python is designed to be installed side-by-side.
Were you to make a module map for python3 you should name it `CPython3`.


## System Libraries With Optional Dependencies

At this time you will need to make another module map package to represent system packages that are built with optional dependencies.

For example, `libarchive` optionally depends on `xz`, which means it can be compiled with `xz` support, but it is not required. To provide a package that uses libarchive with xz you must make a `CArchive+CXz` package that depends on `CXz` and provides `CArchive`.
