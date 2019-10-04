# Unicode

This fixture makes extensive use of exotic Unicode. While deliberately trying to break a as many common false assumptions as possible, *this is a valid package*, and clients are encouraged to test their functionality with it. A tool that successfully handles this package is unlikely to encounter problems with any real‐world package in any human language.

The neighbouring package `UnicodeDependency‐πשּׁµ𝄞🇺🇳🇮🇱x̱̱̱̱̱̄̄̄̄̄` must be placed next this package and tagged with version 1.0.0. (This is necessary to use Unicode in dependency URLs in this package’s manifest.)

Sandboxing likely needs to be disabled to load this package ( `--disable-sandbox`). The latter part of the manifest writes into the `Sources` directory. See the end of the manifest for an explanation. (To temporarily make the fixture compatible with a sandbox for some reason, the latter part of the manifest can be commented out.)
