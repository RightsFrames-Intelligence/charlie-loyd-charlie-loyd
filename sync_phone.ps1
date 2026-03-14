param(
    [string]$PinnedSerial = 'RZGYB1ZZSCD',
    [string]$LocalPath = 'C:\PentagonEncrypted\charlie-loyd-charlie-loyd',
    [string]$RemotePath = '/sdcard/CHARLIE 2.0 CODES',
    [int]$ListFirst = 25,
    [int]$TopLargest = 10,
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & adb @Arguments
}

function Test-AdbDevice {
    param([string]$Serial)

    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        throw 'adb not found in PATH.'
    }

    $state = (Invoke-Adb -s $Serial get-state 2>$null | Out-String).Trim()
    if ($state -ne 'device') {
        throw "ADB device not ready for serial: $Serial"
    }
}

function Quote-RemotePath {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'\\''") + "'"
}

function Get-RemoteStatValue {
    param(
        [string]$Serial,
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
        $value = (Invoke-Adb -s $Serial shell $command 2>$null | Out-String).Trim()
        if ($value) {
            return $value
        }
    }

    return $null
}

function Get-RemoteMTime {
    param(
        [string]$Serial,
        [string]$RemoteFile
    )

    $value = Get-RemoteStatValue -Serial $Serial -RemoteFile $RemoteFile -Format '%Y'
    if ($value -match '^\d+$') {
        return [int64]$value
    }

    return $null
}

function Get-RemoteSize {
    param(
        [string]$Serial,
        [string]$RemoteFile
    )

    $value = Get-RemoteStatValue -Serial $Serial -RemoteFile $RemoteFile -Format '%s'
    if ($value -match '^\d+$') {
        return [int64]$value
    }

    return $null
}

function Ensure-RemoteDirectory {
    param(
        [string]$Serial,
        [string]$RemoteDirectory
    )

    $escaped = Quote-RemotePath -Value $RemoteDirectory
    Invoke-Adb -s $Serial shell "mkdir -p $escaped" | Out-Null
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

Test-AdbDevice -Serial $PinnedSerial

if (-not (Test-Path -LiteralPath $LocalPath)) {
    throw "LocalPath not found: $LocalPath"
}

$localRoot = (Resolve-Path -LiteralPath $LocalPath).Path.TrimEnd('\', '/')
$remoteRoot = $RemotePath.TrimEnd('/')

$files = Get-ChildItem -LiteralPath $localRoot -File -Recurse -ErrorAction Stop |
    Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' }

$results = foreach ($file in $files) {
    $mapping = Get-RelativeRemoteFile -LocalRoot $localRoot -File $file -RemoteRoot $remoteRoot
    $localEpoch = [DateTimeOffset]::new($file.LastWriteTimeUtc).ToUnixTimeSeconds()
    $remoteEpoch = Get-RemoteMTime -Serial $PinnedSerial -RemoteFile $mapping.RemoteFile

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

$missing = @($results | Where-Object Status -eq 'MissingRemote')
$newer = @($results | Where-Object Status -eq 'LocalNewer')
$upToDate = @($results | Where-Object Status -eq 'RemoteUpToDate')
$needed = @($results | Where-Object Status -ne 'RemoteUpToDate')

[pscustomobject]@{
    LocalRoot = $localRoot
    RemoteRoot = $remoteRoot
    TotalLocalFiles = $results.Count
    MissingRemote = $missing.Count
    LocalNewer = $newer.Count
    RemoteUpToDate = $upToDate.Count
    NeedsCopyTotal = $needed.Count
    Preview = [bool]$Preview
} | Format-List

""
"FIRST $ListFirst FILES NEEDING COPY:"
$needed |
    Sort-Object Status, RelativePath |
    Select-Object -First $ListFirst Status, SizeMB, LocalUtc, RelativePath, RemoteFile |
    Format-Table -AutoSize

""
"TOP $TopLargest LARGEST FILES NEEDING COPY:"
$needed |
    Sort-Object SizeBytes -Descending |
    Select-Object -First $TopLargest Status, SizeMB, RelativePath, RemoteFile |
    Format-Table -AutoSize

if ($Preview -or $needed.Count -eq 0) {
    return
}

""
"SYNCING FILES TO PHONE..."

$copied = New-Object System.Collections.Generic.List[object]

foreach ($item in $needed) {
    $remoteDirectory = Get-RemoteDirectory -RemoteFile $item.RemoteFile
    Ensure-RemoteDirectory -Serial $PinnedSerial -RemoteDirectory $remoteDirectory

    Invoke-Adb -s $PinnedSerial push $item.LocalFile $item.RemoteFile | Out-Null

    $remoteSize = Get-RemoteSize -Serial $PinnedSerial -RemoteFile $item.RemoteFile
    if ($remoteSize -ne $item.SizeBytes) {
        throw "Size verification failed for $($item.RelativePath): local=$($item.SizeBytes) remote=$remoteSize"
    }

    $copied.Add([pscustomobject]@{
        Status = $item.Status
        SizeMB = $item.SizeMB
        RelativePath = $item.RelativePath
        RemoteFile = $item.RemoteFile
    }) | Out-Null
}

""
"SYNC COMPLETE:"
$copied | Format-Table -AutoSize
