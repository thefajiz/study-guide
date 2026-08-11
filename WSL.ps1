param (
    [string]$Action,
    [string]$AppName,
    [string]$BinaryPath,
    [string]$LogFilePath = "C:\ProgramData\ArrayIntuneApps\WSLUbuntuLog.txt"
)

$distroName = "Array-Linux-GoldenImage"
$installPath = "C:\WSL\Array-Linux-GoldenImage"

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
    $distroNames = New-Object System.Collections.Generic.List[string]
    $output = @(& wsl.exe --list --quiet 2>$null)
    foreach ($line in $output) {
        if ($null -ne $line) {
            $trimmed = $line.ToString().Trim()
            if ($trimmed -and $trimmed -notmatch "^Windows Subsystem for Linux") {
                if (-not $distroNames.Contains($trimmed)) {
                    $distroNames.Add($trimmed)
                }
            }
        }
    }
    return @($distroNames)
}

function Is-DistroInstalled {
    $currentList = Get-InstalledDistros
    return $currentList -contains $distroName
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
    Log-Message "Testing that $distroName can start."
    $output = @(& wsl.exe --distribution $distroName --exec uname -r 2>&1)
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
    return $true
}

function Remove-DistroCleanly {
    param ([string]$TargetDistro)
    Log-Message "Preparing to purge distro: $TargetDistro"
    $maxAttempts = 3
    $unregistered = $false
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $currentDistros = Get-InstalledDistros
        if ($currentDistros -notcontains $TargetDistro) {
            $unregistered = $true
            break
        }
        Log-Message "Unregister attempt $attempt of $maxAttempts for $TargetDistro."
        
        # Force-kill user-space background hosts holding file locks on the distro
        Stop-Process -Name "wslhost" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1

        $unregisterOutput = @(& wsl.exe --unregister $TargetDistro 2>&1)
        if ($LASTEXITCODE -eq 0) {
            $unregistered = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    return $unregistered
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
# Main Execution Block
# =========================================================

try {
    if ($Action -eq "Install") {
        Log-Message "Starting clean-slate installation of $AppName."
        
        # 1. Force Shutdown to Release File Locks globally
        Log-Message "Executing global WSL shutdown."
        & wsl.exe --shutdown 2>&1 | Out-Null
        Stop-Process -Name "wslhost" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # 2. Detect and Purge ALL Existing Distributions
        $existingDistros = Get-InstalledDistros
        if ($existingDistros.Count -gt 0) {
            foreach ($distro in $existingDistros) {
                $null = Remove-DistroCleanly -TargetDistro $distro
            }
        }

        # 3. Storage Directory Deep Clean
        if (Test-Path -LiteralPath $installPath) {
            try {
                Remove-Item -LiteralPath $installPath -Recurse -Force -ErrorAction Stop
            }
            catch {
                Log-Message "ERROR: Failed to wipe folder $installPath."
                exit 1
            }
        }
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null

        # 4. Clean Import of the Corporate Golden Image
        $importArgs = @("--import", $distroName, $installPath, $BinaryPath, "--version", "2")
        $importSuccess = Invoke-WSLCommand -Arguments $importArgs -Description "Golden Image Import"
        if (-not $importSuccess) {
            exit 1
        }

        # 5. Set as system default
        & wsl.exe --set-default $distroName 2>&1 | Out-Null

        # 6. Post-Installation Check
        if (-not (Test-DistroOperational)) {
            exit 1
        }

        Log-Message "SUCCESS: Deployment completed."
        exit 0
    }
    elseif ($Action -eq "Uninstall") {
        Log-Message "Starting uninstallation of $AppName."
        $cleanupSuccess = Remove-DistroCleanly -TargetDistro $distroName
        if ($cleanupSuccess) {
            exit 0
        }
        exit 1
    }
}
catch {
    Log-Message "UNHANDLED CRITICAL EXCEPTION: $($_.Exception.Message)"
    exit 1
}
