swift run swift-build-prebuilts --stage-dir ~/swift/stage --build --test-signing \
    --version 600.0.1 \
    --version 601.0.1 \
    --version $(git ls-remote --tags https://github.com/swiftlang/swift-syntax '*.*.*' | cut -d '/' -f 3 | grep ^602 | tail -1)
