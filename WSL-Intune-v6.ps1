param (
    [ValidateSet("Install", "Uninstall")]
    [string]$Action,

    [string]$AppName = "WSL Ubuntu",

    [string]$BinaryPath,

    [string]$LogFilePath = "C:\ProgramData\ArrayIntuneApps\WSLUbuntuLog.txt"
)

# =========================================================
# Configuration
# =========================================================

$distroName  = "Array-Linux-GoldenImage"
$installPath = "C:\WSL\Array-Linux-GoldenImage"

# =========================================================
# Logging
# =========================================================

function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $logFolder = Split-Path -Path $LogFilePath -Parent

    try {
        if (-not (Test-Path -LiteralPath $logFolder)) {
            New-Item -ItemType Directory -Path $logFolder -Force -ErrorAction Stop | Out-Null
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $entry = "$timestamp - $Message"

        Write-Output $entry
        Add-Content -LiteralPath $LogFilePath -Value $entry -ErrorAction Stop
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

    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    return @(
        $output |
        ForEach-Object {
            $_.ToString().Trim()
        } |
        Where-Object {
            $_ -and $_ -notmatch "^Windows Subsystem for Linux"
        }
    )
}

function Test-DistroInstalled {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetDistro
    )

    return @(Get-InstalledDistros) -contains $TargetDistro
}

function Get-UbuntuDistros {
    # Remove Ubuntu distributions only.
    # Examples matched:
    #   Ubuntu
    #   Ubuntu-24.04
    #   Ubuntu-22.04
    #
    # Examples intentionally NOT matched:
    #   docker-desktop
    #   docker-desktop-data
    #   Debian
    #   Kali-Linux
    $distros = @(Get-InstalledDistros)

    return @(
        $distros | Where-Object {
            $_ -match '(?i)^Ubuntu(?:$|[-_])'
        }
    )
}

function Get-ManagedCleanupDistros {
    $cleanup = @()

    # Always include the organization's managed distro if present.
    if (Test-DistroInstalled -TargetDistro $distroName) {
        $cleanup += $distroName
    }

    # Also remove all Ubuntu distributions.
    foreach ($ubuntu in @(Get-UbuntuDistros)) {
        if ($cleanup -notcontains $ubuntu) {
            $cleanup += $ubuntu
        }
    }

    return @($cleanup | Select-Object -Unique)
}

function Invoke-WSLCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Description
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

function Stop-WSL {
    Log-Message "Shutting down WSL."

    $output = @(& wsl.exe --shutdown 2>&1)
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if ($null -ne $line -and $line.ToString().Trim()) {
            Log-Message "WSL shutdown: $($line.ToString().Trim())"
        }
    }

    if ($exitCode -ne 0) {
        Log-Message "ERROR: wsl --shutdown failed with exit code $exitCode."
        return $false
    }

    Start-Sleep -Seconds 2
    return $true
}

function Remove-Distro {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetDistro
    )

    if (-not (Test-DistroInstalled -TargetDistro $TargetDistro)) {
        Log-Message "Distro '$TargetDistro' is not registered."
        return $true
    }

    Log-Message "Unregistering distro '$TargetDistro'."

    $output = @(& wsl.exe --unregister $TargetDistro 2>&1)
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if ($null -ne $line -and $line.ToString().Trim()) {
            Log-Message "WSL unregister: $($line.ToString().Trim())"
        }
    }

    if ($exitCode -ne 0) {
        Log-Message "ERROR: Failed to unregister '$TargetDistro'. Exit code $exitCode."
        return $false
    }

    Start-Sleep -Seconds 2

    if (Test-DistroInstalled -TargetDistro $TargetDistro) {
        Log-Message "ERROR: '$TargetDistro' is still registered after unregister."
        return $false
    }

    Log-Message "Verified '$TargetDistro' is no longer registered."
    return $true
}

function Remove-SelectedDistros {
    param (
        [string[]]$Distros
    )

    $allSucceeded = $true

    foreach ($target in @($Distros | Select-Object -Unique)) {
        if (-not (Remove-Distro -TargetDistro $target)) {
            $allSucceeded = $false
        }
    }

    return $allSucceeded
}

function Remove-ManagedFiles {
    if (-not (Test-Path -LiteralPath $installPath)) {
        Log-Message "Managed installation directory does not exist."
        return $true
    }

    Log-Message "Removing managed installation directory: $installPath"

    try {
        Remove-Item -LiteralPath $installPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        Log-Message "ERROR: Failed to remove '$installPath'. $($_.Exception.Message)"
        return $false
    }

    if (Test-Path -LiteralPath $installPath) {
        Log-Message "ERROR: Installation directory still exists after cleanup."
        return $false
    }

    Log-Message "Verified managed installation directory was removed."
    return $true
}

function Test-DistroOperational {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetDistro
    )

    Log-Message "Testing that '$TargetDistro' can start."

    $output = @(
        & wsl.exe --distribution $TargetDistro --exec uname -r 2>&1
    )
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if ($null -ne $line -and $line.ToString().Trim()) {
            Log-Message "Linux kernel: $($line.ToString().Trim())"
        }
    }

    if ($exitCode -ne 0) {
        Log-Message "ERROR: '$TargetDistro' could not be started. Exit code: $exitCode."
        return $false
    }

    $kernel = (
        $output |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { $_ } |
        Select-Object -First 1
    )

    if (-not $kernel) {
        Log-Message "ERROR: Distro started but returned no kernel information."
        return $false
    }

    if ($kernel -match "microsoft-standard-WSL2") {
        Log-Message "WSL 2 kernel confirmed."
    }
    else {
        Log-Message "WARNING: Distro started successfully, but kernel string did not contain the expected WSL2 marker."
        Log-Message "Kernel reported: $kernel"
    }

    return $true
}

function Test-Ubuntu24 {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetDistro
    )

    Log-Message "Verifying Ubuntu 24.04 identity."

    $output = @(
        & wsl.exe --distribution $TargetDistro --exec sh -c "cat /etc/os-release" 2>&1
    )
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if ($null -ne $line -and $line.ToString().Trim()) {
            Log-Message "OS: $($line.ToString().Trim())"
        }
    }

    if ($exitCode -ne 0) {
        Log-Message "ERROR: Could not read /etc/os-release."
        return $false
    }

    $osRelease = $output -join "`n"

    if ($osRelease -notmatch '(^|\r?\n)ID=ubuntu(\r?\n|$)' -or
        $osRelease -notmatch '(^|\r?\n)VERSION_ID="24\.04"(\r?\n|$)') {
        Log-Message "ERROR: Imported distro is not Ubuntu 24.04."
        return $false
    }

    Log-Message "Ubuntu 24.04 confirmed."
    return $true
}

# =========================================================
# Validation
# =========================================================

if ($Action -eq "Install") {

    if (-not $BinaryPath) {
        Log-Message "ERROR: -BinaryPath is required for Install."
        exit 1
    }

    if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        Log-Message "ERROR: TAR file not found: $BinaryPath"
        exit 1
    }
}

# =========================================================
# INSTALL
# =========================================================

if ($Action -eq "Install") {

    Log-Message "========================================"
    Log-Message "Starting installation of $AppName. This package removes Ubuntu distributions only; Docker Desktop and unrelated WSL distributions are preserved."
    Log-Message "Managed distro: $distroName"
    Log-Message "Install path: $installPath"
    Log-Message "========================================"

    # Check WSL availability.
    Log-Message "Checking WSL availability."

    $statusOutput = @(& wsl.exe --status 2>&1)
    $statusExitCode = $LASTEXITCODE

    foreach ($line in $statusOutput) {
        if ($null -ne $line -and $line.ToString().Trim()) {
            Log-Message "WSL status: $($line.ToString().Trim())"
        }
    }

    if ($statusExitCode -ne 0) {
        Log-Message "ERROR: WSL is not available. Exit code: $statusExitCode."
        exit 1
    }

    # Resolve the TAR to an absolute path before any WSL changes.
    try {
        $tarFile = (Resolve-Path -LiteralPath $BinaryPath -ErrorAction Stop).Path
    }
    catch {
        Log-Message "ERROR: Could not resolve TAR path. $($_.Exception.Message)"
        exit 1
    }

    Log-Message "Using TAR file: $tarFile"

    # Stop WSL before replacing the managed distro.
    if (-not (Stop-WSL)) {
        exit 1
    }

    # Remove ALL Ubuntu distributions and the organization's managed distro.
    # Docker Desktop and unrelated distributions are intentionally preserved.
    $cleanupTargets = @(Get-ManagedCleanupDistros)

    if ($cleanupTargets.Count -gt 0) {
        Log-Message "The following Ubuntu/managed distributions will be removed:"
        foreach ($target in $cleanupTargets) {
            Log-Message "  - $target"
        }

        if (-not (Remove-SelectedDistros -Distros $cleanupTargets)) {
            Log-Message "ERROR: One or more Ubuntu/managed distributions could not be removed. Installation aborted."
            exit 1
        }
    }
    else {
        Log-Message "No existing Ubuntu/managed distributions found."
    }

    # Remove the organization's installation directory only after its managed
    # distro has been successfully unregistered.
    if (-not (Remove-ManagedFiles)) {
        Log-Message "ERROR: Old managed installation files could not be removed. Installation aborted."
        exit 1
    }

    # Create a clean installation directory.
    try {
        Log-Message "Creating clean install directory: $installPath"
        New-Item -ItemType Directory -Path $installPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Log-Message "ERROR: Failed to create install directory. $($_.Exception.Message)"
        exit 1
    }

    # Import the golden image explicitly as WSL 2.
    $importArguments = @(
        "--import",
        $distroName,
        $installPath,
        $tarFile,
        "--version",
        "2"
    )

    if (-not (Invoke-WSLCommand -Arguments $importArguments -Description "WSL golden image import")) {
        Log-Message "ERROR: Golden image import failed."

        # Clean up a partial registration if one exists.
        if (Test-DistroInstalled -TargetDistro $distroName) {
            [void](Stop-WSL)
            [void](Remove-Distro -TargetDistro $distroName)
        }

        [void](Remove-ManagedFiles)
        exit 1
    }

    # Verify registration.
    if (-not (Test-DistroInstalled -TargetDistro $distroName)) {
        Log-Message "ERROR: Import returned success, but managed distro is not registered."
        [void](Remove-ManagedFiles)
        exit 1
    }

    # Set managed distro as the default WSL distro.
    Log-Message "Setting '$distroName' as the default WSL distribution."

    $defaultOutput = @(& wsl.exe --set-default $distroName 2>&1)
    $defaultExitCode = $LASTEXITCODE

    foreach ($line in $defaultOutput) {
        if ($null -ne $line -and $line.ToString().Trim()) {
            Log-Message "WSL default: $($line.ToString().Trim())"
        }
    }

    if ($defaultExitCode -ne 0) {
        Log-Message "ERROR: Failed to set managed distro as default."
        [void](Stop-WSL)
        [void](Remove-Distro -TargetDistro $distroName)
        [void](Remove-ManagedFiles)
        exit 1
    }

    # Functional verification.
    if (-not (Test-DistroOperational -TargetDistro $distroName)) {
        Log-Message "ERROR: Imported distro is registered but failed operational verification."
        [void](Stop-WSL)
        [void](Remove-Distro -TargetDistro $distroName)
        [void](Remove-ManagedFiles)
        exit 1
    }

    # Verify the golden image is specifically Ubuntu 24.04.
    if (-not (Test-Ubuntu24 -TargetDistro $distroName)) {
        Log-Message "ERROR: Golden image is not Ubuntu 24.04. Installation aborted."
        [void](Stop-WSL)
        [void](Remove-Distro -TargetDistro $distroName)
        [void](Remove-ManagedFiles)
        exit 1
    }

    Log-Message "========================================"
    Log-Message "$AppName installation completed successfully."
    Log-Message "Managed distro: $distroName"
    Log-Message "========================================"

    exit 0
}

# =========================================================
# UNINSTALL
# =========================================================

if ($Action -eq "Uninstall") {

    Log-Message "========================================"
    Log-Message "Starting uninstallation of $AppName. This package removes Ubuntu distributions only; Docker Desktop and unrelated WSL distributions are preserved."
    Log-Message "Managed distro: $distroName"
    Log-Message "Install path: $installPath"
    Log-Message "========================================"

    if (-not (Stop-WSL)) {
        Log-Message "ERROR: Could not shut down WSL. Uninstallation aborted."
        exit 1
    }

    # Remove ALL Ubuntu distributions and the organization's managed distro.
    # Docker Desktop and unrelated distributions are intentionally preserved.
    $cleanupTargets = @(Get-ManagedCleanupDistros)

    if ($cleanupTargets.Count -gt 0) {
        Log-Message "The following Ubuntu/managed distributions will be removed:"
        foreach ($target in $cleanupTargets) {
            Log-Message "  - $target"
        }

        if (-not (Remove-SelectedDistros -Distros $cleanupTargets)) {
            Log-Message "ERROR: One or more Ubuntu/managed distributions could not be unregistered."
            exit 1
        }
    }
    else {
        Log-Message "No Ubuntu/managed distributions are registered."
    }

    # Remove any remaining files/folders belonging to our managed deployment.
    if (-not (Remove-ManagedFiles)) {
        Log-Message "ERROR: Managed installation files could not be completely removed."
        exit 1
    }

    # Final verification: managed distro must be gone.
    if (Test-DistroInstalled -TargetDistro $distroName) {
        Log-Message "ERROR: Managed distro is still registered after uninstall."
        exit 1
    }

    # Final verification: no Ubuntu distro should remain.
    $remainingUbuntu = @(Get-UbuntuDistros)
    if ($remainingUbuntu.Count -gt 0) {
        Log-Message "ERROR: Ubuntu distributions are still registered after uninstall:"
        foreach ($remaining in $remainingUbuntu) {
            Log-Message "  - $remaining"
        }
        exit 1
    }

    if (Test-Path -LiteralPath $installPath) {
        Log-Message "ERROR: Managed installation path still exists after uninstall."
        exit 1
    }

    Log-Message "========================================"
    Log-Message "$AppName uninstallation completed successfully."
    Log-Message "Distro and managed files are confirmed removed."
    Log-Message "========================================"

    exit 0
}
