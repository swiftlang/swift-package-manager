# Windows Self-Hosted Test

Here are some steps the worked running on Windows.

1. Install Docker on a Windows host and ensure it's configured to run Windows containers
2. Launch a `powershell.exe` session
3. Run the following in power shell to start a container running the nightly toolchain
    ```
    docker run --pull always --rm --interactive --tty swiftlang/swift:nightly-6.3-windowsservercore-1809 powershell.exe
    ```
4. When the container start, clone the "merged" PR to `C:\source`
    ```
    mkdir C:\source
    cd C:\source
    git clone https://github.com/swiftlang/swift-package-manager .
    # Assign the PR ID to a variable
    $PR_ID = "8288"
    git fetch origin pull/$PR_ID/merge
    git checkout FETCH_HEAD
    ```
5. Run the CI pipeline script
    ```
    python C:\source\Utilities\build-using-self  --enable-swift-testing --enable-xctest
    ```


## Get all processes, including transitive PID, for a given Process ID

1. Launch a PowerShell session
1. Find the parent PID by running `Get-CimInstance Win32_Process | Select-Object ProcessId, Name, CommandLine | Format-Table -AutoSize`
1. Assign the process ID to a variable
    ```
    $ParentPID = 1234  # Replace with your actual PID
    ```
1. Define a function that will get transitive process ID
    ```
    function Get-TransitiveChildren ($pidList) {
        if ($pidList.Count -eq 0) { return }

        # Fetch direct children and their command lines
        $children = Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -in $pidList }

        if ($children) {
            # Output current level
            $children | Select-Object ProcessId, Name, CommandLine

            # Recursively find next level of children
            Get-TransitiveChildren -pidList $children.ProcessId
        }
    }
    ```
1. Start the recursive search
    ```
    Get-TransitiveChildren -pidList @($ParentPID) | Format-Table -AutoSize
    ```
