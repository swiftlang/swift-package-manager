##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2026 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

# Wraps a swift test invocation with an internal timeout. If the internal
# timeout fires before the GitHub Actions job-level timeout, a snapshot of
# running swift* processes and descendants of the test process is written to
# the log and to a file, then the process tree is terminated.

param (
    [int]$TimeoutMinutes = 200,
    [Parameter(Mandatory = $true)]
    [string]$Command
)

$ErrorActionPreference = 'Continue'

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
Write-Host "=== run-swift-test.ps1 ==="
Write-Host "Internal timeout : $TimeoutMinutes minutes"
Write-Host "Deadline         : $deadline"
Write-Host "Command          : $Command"
Write-Host ""

$proc = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $Command -PassThru -NoNewWindow
$rootPid = $proc.Id
Write-Host "Started wrapper process with PID $rootPid"

$timedOut = $false
while (-not $proc.HasExited) {
    if ((Get-Date) -ge $deadline) {
        $timedOut = $true
        break
    }
    Start-Sleep -Seconds 30
}

if (-not $timedOut) {
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
    Write-Host "=== run-swift-test.ps1: child exited with code $exitCode ==="
    exit $exitCode
}

Write-Host ""
Write-Host "::error::Internal timeout of $TimeoutMinutes minutes exceeded; collecting diagnostics"
Write-Host ""

try {
    $all = Get-CimInstance Win32_Process |
        Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine, CreationDate

    # Compute the set of descendants of the root PID via BFS over parent links.
    $descendants = [System.Collections.Generic.HashSet[int]]::new()
    [void]$descendants.Add($rootPid)
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($p in $all) {
            $ppid = [int]$p.ParentProcessId
            $cpid = [int]$p.ProcessId
            if ($descendants.Contains($ppid) -and -not $descendants.Contains($cpid)) {
                [void]$descendants.Add($cpid)
                $changed = $true
            }
        }
    }

    # Include any swift* process even if it's not a descendant (e.g., orphaned
    # by parent exit).
    $snapshot = $all | Where-Object {
        $descendants.Contains([int]$_.ProcessId) -or ($_.Name -like 'swift*')
    } | Sort-Object ProcessId

    Write-Host "=== Process snapshot (descendants of PID $rootPid, plus any swift*) ==="
    $snapshot |
        Format-Table ProcessId, ParentProcessId, Name, CreationDate, CommandLine -AutoSize -Wrap |
        Out-String -Width 4096 |
        Write-Host

    $outFile = Join-Path $PWD 'timeout-process-snapshot.txt'
    $snapshot | Format-List * | Out-File -FilePath $outFile -Encoding utf8
    Write-Host "Snapshot written to: $outFile"

    Write-Host ""
    Write-Host "=== Contents of $outFile ==="
    Get-Content -LiteralPath $outFile | Write-Host
}
catch {
    Write-Host "Failed to collect diagnostics: $_"
}

Write-Host ""
Write-Host "=== Terminating process tree rooted at PID $rootPid ==="
foreach ($id in $descendants) {
    try {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    } catch { }
}

exit 124
