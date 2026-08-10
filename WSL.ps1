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
    param (
        [string]$Message
    )

    $LogFolder = Split-Path $LogFilePath -Parent

    if (-not (Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
    }

    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType File -Path $LogFilePath -Force | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp - $Message"

    Write-Output $LogEntry
    Add-Content -Path $LogFilePath -Value $LogEntry
}

# =========================================================
# Detection
# =========================================================

function Is-DistroInstalled {

    try {

        $Result = wsl --list --quiet 2>$null | Out-String

        if ($Result -like "*$distroName*") {
            return $true
        }

        return $false
    }
    catch {

        return $false
    }
}
# =========================================================
# Validation
# =========================================================

if (-not $Action) {
    Log-Message "ERROR: No action specified."
    exit 1
}

if ($Action -eq "Install") {

    if (-not $BinaryPath) {
        Log-Message "ERROR: No binary path specified."
        exit 1
    }

    if (-not (Test-Path $BinaryPath)) {
        Log-Message "ERROR: Binary path not found."
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

            Log-Message "Checking WSL availability"

            wsl --status | Out-Null

            Log-Message "Updating WSL"

            wsl --update | Out-Null

            if (-not (Test-Path $installPath)) {
                New-Item -ItemType Directory -Path $installPath -Force | Out-Null
            }

            $TarFile = (Resolve-Path $BinaryPath).Path

            Log-Message "Importing distro $distroName"

            wsl --import `
                $distroName `
                $installPath `
                $TarFile `
                --version 2

            Start-Sleep -Seconds 5

            if (Is-DistroInstalled) {
                Log-Message "$AppName installation completed successfully."
                exit 0
            }

            Log-Message "ERROR: Installation failed."
            exit 1
        }

        "Uninstall" {

            Log-Message "Starting uninstallation"

            wsl --shutdown 2>$null

            Start-Sleep -Seconds 2

            if (Is-DistroInstalled) {

                Log-Message "Unregistering distro $distroName"

                wsl --unregister $distroName

                Start-Sleep -Seconds 5
            }

            if (Test-Path $installPath) {

                Log-Message "Removing local files"

                Remove-Item `
                    -Path $installPath `
                    -Recurse `
                    -Force `
                    -ErrorAction SilentlyContinue
            }

            Start-Sleep -Seconds 2

            if (-not (Is-DistroInstalled)) {
                Log-Message "$AppName uninstallation completed successfully."
                exit 0
            }

            Log-Message "ERROR: Distro still registered."
            exit 1
        }

        Default {

            Log-Message "ERROR: Invalid action specified."
            exit 1
        }
    }
}
catch {

    Log-Message "ERROR: $($_.Exception.Message)"
    exit 1
}