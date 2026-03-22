param(
    [string]$Serial,
    [string]$LocalPath = $PSScriptRoot,
    [string]$RemotePath = '/sdcard/CHARLIE 2.0 CODES',
    [int]$ListFirst = 25,
    [int]$TopLargest = 10,
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    param(
        [switch]$IgnoreExitCode,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $global:LASTEXITCODE = 0
    $output = & adb @Arguments
    $exitCode = $LASTEXITCODE

    if (-not $IgnoreExitCode -and $exitCode -ne 0) {
        $commandLine = @('adb') + $Arguments
        throw "adb exited with code ${exitCode}: $($commandLine -join ' ')"
    }

    return $output
}

function Get-DefaultSerial {
    $devices = @(Invoke-Adb -IgnoreExitCode devices | Select-Object -Skip 1 | ForEach-Object { ($_ | Out-String).Trim() } | Where-Object { $_ -match '\sdevice$' })
    if ($devices.Count -eq 1) {
        return ($devices[0] -split '\s+')[0]
    }
    if ($devices.Count -eq 0) {
        throw 'No authorized ADB device detected.'
    }
    throw 'Multiple ADB devices detected. Pass -Serial explicitly.'
}

function Test-AdbDevice {
    param([string]$ResolvedSerial)

    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        throw 'adb not found in PATH.'
    }

    $state = (Invoke-Adb -s $ResolvedSerial get-state 2>$null | Out-String).Trim()
    if ($state -ne 'device') {
        throw "ADB device not ready for serial: $ResolvedSerial"
    }
}

function Quote-RemotePath {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'\\''") + "'"
}

function Get-RemoteStatValue {
    param(
        [string]$ResolvedSerial,
        [string]$RemoteFile,
        [string]$Format
    )

    $escaped = Quote-RemotePath -Value $RemoteFile
    $commands = @(
        "toybox stat -c $Format $escaped 2>/dev/null",
        "stat -c $Format $escaped 2>/dev/null",
        "busybox stat -c $Format $escaped 2>/dev/null"
    )

    foreach ($command in $commands) {
        $value = (Invoke-Adb -IgnoreExitCode -s $ResolvedSerial shell $command 2>$null | Out-String).Trim()
        if ($value) {
            return $value
        }
    }

    return $null
}

function Get-RemoteMTime {
    param(
        [string]$ResolvedSerial,
        [string]$RemoteFile
    )

    $value = Get-RemoteStatValue -ResolvedSerial $ResolvedSerial -RemoteFile $RemoteFile -Format '%Y'
    if ($value -match '^\d+$') {
        return [int64]$value
    }

    return $null
}

function Get-RemoteSize {
    param(
        [string]$ResolvedSerial,
        [string]$RemoteFile
    )

    $value = Get-RemoteStatValue -ResolvedSerial $ResolvedSerial -RemoteFile $RemoteFile -Format '%s'
    if ($value -match '^\d+$') {
        return [int64]$value
    }

    return $null
}

function Ensure-RemoteDirectory {
    param(
        [string]$ResolvedSerial,
        [string]$RemoteDirectory
    )

    $escaped = Quote-RemotePath -Value $RemoteDirectory
    Invoke-Adb -s $ResolvedSerial shell "mkdir -p $escaped" | Out-Null
}

function Get-RelativeRemoteFile {
    param(
        [string]$LocalRoot,
        [System.IO.FileInfo]$File,
        [string]$RemoteRoot
    )

    $relativePath = $File.FullName.Substring($LocalRoot.Length).TrimStart('\', '/')
    $remoteFile = ($RemoteRoot.TrimEnd('/') + '/' + ($relativePath -replace '\\', '/')).Replace('//', '/')

    [pscustomobject]@{
        RelativePath = $relativePath
        RemoteFile = $remoteFile
    }
}

function Get-RemoteDirectory {
    param([string]$RemoteFile)

    $lastSlash = $RemoteFile.LastIndexOf('/')
    if ($lastSlash -lt 0) {
        return '.'
    }

    return $RemoteFile.Substring(0, $lastSlash)
}

function Get-SyncCandidates {
    param(
        [string]$ResolvedSerial,
        [string]$LocalRoot,
        [string]$RemoteRoot
    )

    $files = Get-ChildItem -LiteralPath $LocalRoot -File -Recurse -ErrorAction Stop |
        Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' }

    $results = foreach ($file in $files) {
        $mapping = Get-RelativeRemoteFile -LocalRoot $LocalRoot -File $file -RemoteRoot $RemoteRoot
        $localEpoch = [DateTimeOffset]::new($file.LastWriteTimeUtc).ToUnixTimeSeconds()
        $remoteEpoch = Get-RemoteMTime -ResolvedSerial $ResolvedSerial -RemoteFile $mapping.RemoteFile

        $status = if ($null -eq $remoteEpoch) {
            'MissingRemote'
        }
        elseif ($localEpoch -gt $remoteEpoch) {
            'LocalNewer'
        }
        else {
            'RemoteUpToDate'
        }

        [pscustomobject]@{
            Status = $status
            SizeBytes = $file.Length
            SizeMB = [math]::Round($file.Length / 1MB, 2)
            LocalUtc = $file.LastWriteTimeUtc
            RelativePath = $mapping.RelativePath
            RemoteFile = $mapping.RemoteFile
            LocalFile = $file.FullName
        }
    }

    return $results
}

function Invoke-SyncPhone {
    param(
        [string]$ResolvedSerial,
        [string]$SourcePath,
        [string]$DestinationPath,
        [int]$PreviewListFirst,
        [int]$PreviewTopLargest,
        [bool]$IsPreview
    )

    Test-AdbDevice -ResolvedSerial $ResolvedSerial

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "LocalPath not found: $SourcePath"
    }

    $localRoot = (Resolve-Path -LiteralPath $SourcePath).Path.TrimEnd('\', '/')
    $remoteRoot = $DestinationPath.TrimEnd('/')
    $results = @(Get-SyncCandidates -ResolvedSerial $ResolvedSerial -LocalRoot $localRoot -RemoteRoot $remoteRoot)
    $needed = @($results | Where-Object Status -ne 'RemoteUpToDate')

    [pscustomobject]@{
        LocalRoot = $localRoot
        RemoteRoot = $remoteRoot
        Serial = $ResolvedSerial
        TotalLocalFiles = $results.Count
        NeedsCopyTotal = $needed.Count
        Preview = $IsPreview
    } | Format-List

    ""
    "FIRST $PreviewListFirst FILES NEEDING COPY:"
    $needed |
        Sort-Object Status, RelativePath |
        Select-Object -First $PreviewListFirst Status, SizeMB, LocalUtc, RelativePath, RemoteFile |
        Format-Table -AutoSize

    ""
    "TOP $PreviewTopLargest LARGEST FILES NEEDING COPY:"
    $needed |
        Sort-Object SizeBytes -Descending |
        Select-Object -First $PreviewTopLargest Status, SizeMB, RelativePath, RemoteFile |
        Format-Table -AutoSize

    if ($IsPreview -or $needed.Count -eq 0) {
        return
    }

    ""
    "SYNCING FILES TO PHONE..."

    foreach ($item in $needed) {
        $remoteDirectory = Get-RemoteDirectory -RemoteFile $item.RemoteFile
        Ensure-RemoteDirectory -ResolvedSerial $ResolvedSerial -RemoteDirectory $remoteDirectory
        Invoke-Adb -s $ResolvedSerial push $item.LocalFile $item.RemoteFile | Out-Null

        $remoteSize = Get-RemoteSize -ResolvedSerial $ResolvedSerial -RemoteFile $item.RemoteFile
        if ($remoteSize -ne $item.SizeBytes) {
            throw "Size verification failed for $($item.RelativePath): local=$($item.SizeBytes) remote=$remoteSize"
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $resolvedSerial = if ($PSBoundParameters.ContainsKey('Serial') -and -not [string]::IsNullOrWhiteSpace($Serial)) { $Serial } else { Get-DefaultSerial }

    Invoke-SyncPhone `
        -ResolvedSerial $resolvedSerial `
        -SourcePath $LocalPath `
        -DestinationPath $RemotePath `
        -PreviewListFirst $ListFirst `
        -PreviewTopLargest $TopLargest `
        -IsPreview ([bool]$Preview)
}
