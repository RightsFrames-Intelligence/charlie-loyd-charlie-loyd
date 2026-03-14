Describe 'sync_phone helpers' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\sync_phone.ps1')
    }

    It 'shell-escapes single quotes in remote paths' {
        $quoted = Quote-RemotePath -Value "/sdcard/CHARLIE 2.0 CODES/O'Reilly.txt"

        $quoted | Should -Be "'/sdcard/CHARLIE 2.0 CODES/O'\\''Reilly.txt'"
    }

    It 'returns the parent remote directory' {
        $remoteDirectory = Get-RemoteDirectory -RemoteFile '/sdcard/CHARLIE 2.0 CODES/folder/file.txt'

        $remoteDirectory | Should -Be '/sdcard/CHARLIE 2.0 CODES/folder'
    }

    It 'maps local files to normalized remote paths when dot-sourced' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sync-phone-tests-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $nestedDirectory = Join-Path $tempRoot 'docs'
            New-Item -ItemType Directory -Path $nestedDirectory | Out-Null

            $localFilePath = Join-Path $nestedDirectory 'note.txt'
            Set-Content -LiteralPath $localFilePath -Value 'test'

            $fileInfo = Get-Item -LiteralPath $localFilePath
            $mapping = Get-RelativeRemoteFile -LocalRoot $tempRoot -File $fileInfo -RemoteRoot '/sdcard/CHARLIE 2.0 CODES'

            $mapping.RelativePath | Should -Be 'docs\note.txt'
            $mapping.RemoteFile | Should -Be '/sdcard/CHARLIE 2.0 CODES/docs/note.txt'
            (Get-Command Invoke-SyncPhone -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
