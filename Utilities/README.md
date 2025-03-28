# Windows Self-Hosted Test

Here are some steps the worked running on Windows.

1. Install Docker on a Windows host
2. Launch a `Powershell.exe` session
3. Run the following in power shell to start a container running the nightly toolchain
    ```
    docker run --pull always --rm --interactive --tty swiftlang/swift:nightly-main-windowsservercore-1809 powershell.exe
    ```
4. When the container start, clone the "merged" PR to `C:\source`
    ```
    mkdir C:\source
    cd C:\source
    git clone https://github.com/swiftlang/swift-package-manager .
    # Assign the PR ID to a variable
    $PR_ID = "8210"
    git fetch origin pull/$PR_ID/merge:ci_merge_$PR_ID
    git checkout ci_merge_$PR_ID
    ```
5. Run the CI pipeline script
    ```
    python C:\source\Utilities\build-using-self  --enable-swift-testing --enable-xctest
    ```
