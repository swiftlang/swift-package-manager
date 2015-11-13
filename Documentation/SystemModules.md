# System Modules

You can link against system libraries using the package manager.

To do so special packages must be published that contain a module map for that library.

Let’s use the example of `libvorbis`. This is the code we want to compile:

```swift
import CVorbis

let foo = vorbis_version_string()
let bar = String.fromCString(foo)!

print(bar)
```

To `import CVorbis` the package manager requires
that libvorbis has been installed by a system packager, the following files are of
interest:

    /usr/lib/libvorbis.dylib
    /usr/include/vorbis/codec.h

Using our system packager we determine that vorbis depends on libogg, and libogg depends on libc.
We must provide or find packages that provide modules for `vorbis` and `ogg`,
libc also has a module map, but it is
provided by Swift (`Darwin` and `Glibc` on OS X and Linux respectively).

We search but cannot find existing packages for vorbis or ogg, so we must create them ourselves.

Packages that provide module maps for system libraries are handled differently to regular Swift packages.

In a directory called `CVorbis` we add the following single file named `module.map`:

    module CVorbis [system] {
        header "/usr/local/include/vorbis/codec.h"
        link "vorbis"
        export *
    }

The convention we hope the community will adopt is to prefix such modules with `C` and to camelcase the modules
as per Swift module name conventions. Then the community is free to name another module simply `Vorbis` which
contains more “Swifty” function wrappers around the raw C interface.

we must do the same for `libogg`:

    module COgg [system] {
        header "/usr/local/include/ogg/ogg.h"
        link "ogg"
        export *
    }


Note we do not call the module `CLibogg`. In general avoid the lib prefix unless the authors of the package
typically always refer to it that way. A good rule of thumb is to look at the header files, here we can
see the header is called simply "ogg.h". Pay attention to capitalization, note that we provide `CPOSIX` and not
`CPosix`, this is because POSIX is an acronym and is typically spelled all-caps.

Back in our example app we need a `Package.swift` that depends on CVorbis:

```swift
import PackageDescription

let package = Package(
    dependencies: [
        .Package(url: "../CVorbis", majorVersion: 1),
    ]
)
```

While we are developing these packages we can refer to `CVorbis` using a relative file path, but once we publish
this package on the Internet we must also find homes for `COgg` and `CVorbis`.

Now if we type `swift build` in our example app directory we will create an executable:

    $ swift build
    …
    $ .build/debug/example
    Xiph.Org libVorbis 1.3.5
    $


**Take care** you must specify all the headers that a system package uses, ***BUT*** you must not specify headers that are included
from the headers you have already specified. For example with libogg there are three headers but the other two are included from the
umbrella header ogg.h. If you get the includes wrong you will get intermittent and hard to debug compile issues.

#### Cross-platform Module Maps

The package manager will mangle your module map when used to cater to both `/usr` and `/usr/local` installs of system packages.
However this may not be sufficient for all platforms.

Long term we hope that system libraries and system packagers will provide module maps and thus this component of the package
manager will become redundant.

However until then we will (in the near future)
provide a way for module map packages to provide module maps for multiple platforms in the same package.


#### Module Map Versioning

Version the module maps semantically. The meaning of semantic version is less clear here, so use your best judgement.
Do not follow the version of the system library the module map represents, version the module map(s) independently.

Follow the conventions of system packagers, for example, the debian package for python3 is called python3, there is not a single
package for python and python is designed to be installed side-by-side. Where you to make a module map for python3 you should name
it `CPython3`.

### Packages That Provide Multiple Libraries

Vorbis in fact provides three libraries, `libvorbis`, `libvorbisenc` and `libvorbisfile`. The above module map only provides
support for libvorbis (the decoder), to provide modules we must supplement the same module-map:

    module CVorbis [system] {
        header "/usr/local/include/vorbis/codec.h"
        link "vorbis"
        export *
    }

    module CVorbisEncode [system] {
        header "/usr/include/vorbis/vorbisenc.h"
        link "vorbisenc"
        export *
    }

    module CVorbisFile [system] {
        header "/usr/include/vorbis/vorbisfile.h"
        link "vorbisfile"
        export *
    }

`libvorbisencode` and `libvorbisfile` link to `libvorbis`, we don’t need to specify this information in the module-map because
the headers `vorbisenc.h` and `vorbisfile.h` both include `vorbis/codec.h`. It is very important however that those headers
do include their dependent headers, otherwise when the modules are imported into Swift the dependent modules will not get
imported automatically and link errors will happen. If these link errors occur to consumers of a package that consumes your
package the link errors can be especially difficult to debug.

* * *