$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\sync_phone.ps1')

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        $Actual,
        [Parameter(Mandatory = $true)]
        $Expected,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Actual -cne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Actual,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Actual -notmatch $Pattern) {
        throw "$Message Pattern=[$Pattern] Actual=[$Actual]"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        [Parameter(Mandatory = $true)]
        [string]$MessagePattern,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    try {
        & $Action
    }
    catch {
        $errorText = $_.Exception.Message
        if ($errorText -match $MessagePattern) {
            return
        }

        throw "$Message Pattern=[$MessagePattern] Actual=[$errorText]"
    }

    throw "$Message No exception was thrown."
}

function Assert-NotNullOrEmpty {
    param(
        [Parameter(Mandatory = $true)]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($null -eq $Value) {
        throw $Message
    }

    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
        throw $Message
    }
}

function adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    throw 'adb stub was not configured for this test.'
}

$script:FakeAdbExitCode = 0
$script:FakeAdbOutput = ''

Remove-Item Function:\adb -Force -ErrorAction SilentlyContinue
function adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    $global:LASTEXITCODE = $script:FakeAdbExitCode
    return $script:FakeAdbOutput
}

$script:FakeAdbExitCode = 42
$script:FakeAdbOutput = 'failure output'
Assert-Throws -Action { Invoke-Adb devices } -MessagePattern 'adb exited with code 42: adb devices' -Message 'Invoke-Adb should surface adb exit codes.'

$script:FakeAdbExitCode = 1
$script:FakeAdbOutput = 'probe output'
$result = Invoke-Adb -IgnoreExitCode shell 'stat missing'
Assert-Equal -Actual $result -Expected 'probe output' -Message 'Invoke-Adb should allow ignored adb exit codes for probes.'

$quoted = Quote-RemotePath -Value "/sdcard/CHARLIE 2.0 CODES/O'Reilly.txt"
Assert-Equal -Actual $quoted -Expected "'/sdcard/CHARLIE 2.0 CODES/O'\\''Reilly.txt'" -Message 'Quote-RemotePath should escape single quotes.'

$remoteDirectory = Get-RemoteDirectory -RemoteFile '/sdcard/CHARLIE 2.0 CODES/folder/file.txt'
Assert-Equal -Actual $remoteDirectory -Expected '/sdcard/CHARLIE 2.0 CODES/folder' -Message 'Get-RemoteDirectory should return the containing directory.'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sync-phone-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $nestedDirectory = Join-Path $tempRoot 'docs'
    New-Item -ItemType Directory -Path $nestedDirectory | Out-Null

    $localFilePath = Join-Path $nestedDirectory 'note.txt'
    Set-Content -LiteralPath $localFilePath -Value 'test'

    $fileInfo = Get-Item -LiteralPath $localFilePath
    $mapping = Get-RelativeRemoteFile -LocalRoot $tempRoot -File $fileInfo -RemoteRoot '/sdcard/CHARLIE 2.0 CODES'

    Assert-Equal -Actual $mapping.RelativePath -Expected 'docs\note.txt' -Message 'Get-RelativeRemoteFile should preserve the relative path.'
    Assert-Equal -Actual $mapping.RemoteFile -Expected '/sdcard/CHARLIE 2.0 CODES/docs/note.txt' -Message 'Get-RelativeRemoteFile should normalize remote separators.'
    Assert-NotNullOrEmpty -Value (Get-Command Invoke-SyncPhone -ErrorAction SilentlyContinue) -Message 'Invoke-SyncPhone should be available after dot-sourcing.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
    Remove-Item Function:\adb -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
}

Write-Host 'sync_phone tests passed'
