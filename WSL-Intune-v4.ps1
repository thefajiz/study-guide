param (
    [string]$Action,
    [string]$AppName,
    [string]$BinaryPath,
    [string]$LogFilePath = "C:\ProgramData\ArrayIntuneApps\WSLUbuntuLog.txt"
)

$distroName = "Array-Linux-GoldenImage-v1"
$installPath = "C:\WSL\Array-Linux-GoldenImage-v1"

# =========================================================
# Logging
# =========================================================

function Log-Message {
    param ([string]$Message)

    $LogFolder = Split-Path -Path $LogFilePath -Parent

    try {
        if (-not (Test-Path -LiteralPath $LogFolder)) {
            New-Item -ItemType Directory -Path $LogFolder -Force -ErrorAction Stop | Out-Null
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogEntry = "$Timestamp - $Message"

        Write-Output $LogEntry
        Add-Content -LiteralPath $LogFilePath -Value $LogEntry -ErrorAction Stop
    }
    catch {
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - LOGGING ERROR: $($_.Exception.Message)"
    }
}

# =========================================================
# WSL Helpers
# =========================================================

function Get-InstalledDistros {
    $output = @(& wsl.exe --list --quiet 2>$null)
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        return @()
    }

    return @(
        $output |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object {
            $_ -and $_ -notmatch "^Windows Subsystem for Linux"
        }
    )
}

function Is-DistroInstalled {
    return @(Get-InstalledDistros) -contains $distroName
}

function Invoke-WSLCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$Description = "WSL command"
    )

    Log-Message "Running: wsl.exe $($Arguments -join ' ')"

    $output = @(& wsl.exe @Arguments 2>&1)
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if ($null -ne $line -and $line.ToString().Trim()) {
            Log-Message "WSL: $($line.ToString().Trim())"
        }
    }

    if ($exitCode -ne 0) {
        Log-Message "ERROR: $Description failed with exit code $exitCode."
        return $false
    }

    Log-Message "$Description completed successfully."
    return $true
}

function Test-DistroOperational {
    # Instead of parsing the display output of "wsl --list --verbose",
    # launch the imported distro and query its Linux kernel.
    # The import itself explicitly requests WSL 2 with --version 2.
    Log-Message "Testing that $distroName can start."

    $output = @(
        & wsl.exe --distribution $distroName --exec uname -r 2>&1
    )
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if ($null -ne $line -and $line.ToString().Trim()) {
            Log-Message "Linux kernel: $($line.ToString().Trim())"
        }
    }

    if ($exitCode -ne 0) {
        Log-Message "ERROR: Distro could not be started. Exit code: $exitCode."
        return $false
    }

    $kernel = ($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ } | Select-Object -First 1)

    if (-not $kernel) {
        Log-Message "ERROR: Distro started but returned no kernel information."
        return $false
    }

    # WSL 2 normally exposes a Microsoft WSL 2 kernel. We treat this as
    # an additional sanity check; --import --version 2 is the actual
    # installation request.
    if ($kernel -match "WSL2|microsoft-standard") {
        Log-Message "WSL 2 kernel detected successfully."
    }
    else {
        Log-Message "WARNING: Distro started successfully, but the kernel string does not contain the expected WSL 2 marker."
        Log-Message "Kernel reported: $kernel"
        Log-Message "The distro was imported with --version 2; continuing because the operational test succeeded."
    }

    return $true
}

function Remove-DistroCleanly {
    Log-Message "Preparing to remove distro $distroName."

    $shutdownOutput = @(& wsl.exe --shutdown 2>&1)
    $shutdownExitCode = $LASTEXITCODE

    foreach ($line in $shutdownOutput) {
        if ($null -ne $line -and $line.ToString().Trim()) {
            Log-Message "WSL shutdown: $($line.ToString().Trim())"
        }
    }

    if ($shutdownExitCode -ne 0) {
        Log-Message "WARNING: wsl --shutdown returned exit code $shutdownExitCode. Continuing."
    }
    else {
        Log-Message "WSL shutdown completed."
    }

    Start-Sleep -Seconds 2

    $maxAttempts = 3
    $unregistered = $false

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {

        if (-not (Is-DistroInstalled)) {
            Log-Message "Distro $distroName is no longer registered."
            $unregistered = $true
            break
        }

        Log-Message "Unregister attempt $attempt of $maxAttempts for $distroName."

        $unregisterOutput = @(& wsl.exe --unregister $distroName 2>&1)
        $unregisterExitCode = $LASTEXITCODE

        foreach ($line in $unregisterOutput) {
            if ($null -ne $line -and $line.ToString().Trim()) {
                Log-Message "WSL unregister: $($line.ToString().Trim())"
            }
        }

        if ($unregisterExitCode -eq 0) {
            Log-Message "Distro unregister command completed successfully."
            $unregistered = $true
            break
        }

        Log-Message "WARNING: Unregister attempt $attempt failed with exit code $unregisterExitCode."

        if ($attempt -lt $maxAttempts) {
            Start-Sleep -Seconds 3
        }
    }

    if (-not $unregistered -or (Is-DistroInstalled)) {
        Log-Message "ERROR: Distro $distroName is still registered. Local files will NOT be force-deleted."
        return $false
    }

    if (Test-Path -LiteralPath $installPath) {
        Log-Message "Removing remaining local files: $installPath"

        try {
            Remove-Item -LiteralPath $installPath -Recurse -Force -ErrorAction Stop
            Log-Message "Remaining local files removed successfully."
        }
        catch {
            Log-Message "ERROR: Failed to remove $installPath. $($_.Exception.Message)"
            return $false
        }
    }
    else {
        Log-Message "Installation folder does not exist. No local cleanup required."
    }

    if (Is-DistroInstalled) {
        Log-Message "ERROR: Distro is still registered after cleanup."
        return $false
    }

    if (Test-Path -LiteralPath $installPath) {
        Log-Message "ERROR: Installation folder still exists after cleanup."
        return $false
    }

    return $true
}

# =========================================================
# Validation
# =========================================================

if (-not $Action) {
    Log-Message "ERROR: No action specified."
    exit 1
}

if ($Action -notin @("Install", "Uninstall")) {
    Log-Message "ERROR: Invalid action specified: $Action"
    exit 1
}

if ($Action -eq "Install") {
    if (-not $BinaryPath) {
        Log-Message "ERROR: No binary path specified."
        exit 1
    }

    if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        Log-Message "ERROR: TAR file not found: $BinaryPath"
        exit 1
    }
}

# =========================================================
# Main
# =========================================================

try {
    switch ($Action) {

        "Install" {

            if (Is-DistroInstalled) {
                Log-Message "$AppName already installed. Skipping."
                exit 0
            }

            Log-Message "Starting installation of $AppName."
            Log-Message "Distro name: $distroName"
            Log-Message "Install path: $installPath"

            Log-Message "Checking WSL availability."

            $statusOutput = @(& wsl.exe --status 2>&1)
            $statusExitCode = $LASTEXITCODE

            foreach ($line in $statusOutput) {
                if ($null -ne $line -and $line.ToString().Trim()) {
                    Log-Message "WSL status: $($line.ToString().Trim())"
                }
            }

            if ($statusExitCode -ne 0) {
                Log-Message "ERROR: WSL is not available. Exit code: $statusExitCode"
                exit 1
            }

            if (-not (Test-Path -LiteralPath $installPath)) {
                Log-Message "Creating install directory: $installPath"
                New-Item -ItemType Directory -Path $installPath -Force -ErrorAction Stop | Out-Null
            }

            $TarFile = (Resolve-Path -LiteralPath $BinaryPath -ErrorAction Stop).Path
            Log-Message "Using TAR file: $TarFile"

            Log-Message "Importing distro $distroName with WSL version 2."

            $importArguments = @(
                "--import",
                $distroName,
                $installPath,
                $TarFile,
                "--version",
                "2"
            )

            if (-not (Invoke-WSLCommand -Arguments $importArguments -Description "WSL distro import")) {
                Log-Message "ERROR: WSL import failed."

                if (Is-DistroInstalled) {
                    Log-Message "A partial distro registration was detected. Attempting cleanup."
                    [void](Remove-DistroCleanly)
                }

                exit 1
            }

            if (-not (Is-DistroInstalled)) {
                Log-Message "ERROR: Import returned success, but distro is not registered."
                exit 1
            }

            if (-not (Test-DistroOperational)) {
                Log-Message "ERROR: Imported distro is registered but could not be started."
                exit 1
            }

            Log-Message "$AppName installation completed successfully."
            exit 0
        }

        "Uninstall" {

            Log-Message "Starting uninstallation of $AppName."
            Log-Message "Distro name: $distroName"
            Log-Message "Install path: $installPath"

            if (-not (Is-DistroInstalled)) {
                Log-Message "Distro $distroName is not registered. Checking for leftover files."

                if (Test-Path -LiteralPath $installPath) {
                    Log-Message "Removing leftover installation files."

                    try {
                        Remove-Item -LiteralPath $installPath -Recurse -Force -ErrorAction Stop
                    }
                    catch {
                        Log-Message "ERROR: Failed to remove leftover files. $($_.Exception.Message)"
                        exit 1
                    }
                }

                if (-not (Test-Path -LiteralPath $installPath)) {
                    Log-Message "$AppName is already uninstalled. Cleanup completed."
                    exit 0
                }

                Log-Message "ERROR: Installation folder still exists."
                exit 1
            }

            if (Remove-DistroCleanly) {
                Log-Message "$AppName uninstallation completed successfully."
                exit 0
            }

            Log-Message "ERROR: $AppName uninstallation failed. Review the log for details."
            exit 1
        }
    }
}
catch {
    Log-Message "ERROR: Unexpected exception: $($_.Exception.Message)"
    exit 1
}
