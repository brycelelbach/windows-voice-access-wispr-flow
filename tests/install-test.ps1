[CmdletBinding()]
param([switch]$ExerciseProcess)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'install.ps1'
$profile = Join-Path ([IO.Path]::GetTempPath()) ("wispr-mode-test-" + [guid]::NewGuid())
$config = Join-Path $profile 'VoiceAccess\CustomCommands\en-US\CustomCommands.json'
$utf8 = [Text.UTF8Encoding]::new($false)
function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function Read-Config { Get-Content -LiteralPath $config -Raw | ConvertFrom-Json }
function Run-Setup { & $installer -ProfileRoot $profile -NoStart:(!$ExerciseProcess) }
try {
    $result = Run-Setup
    Assert $result.ConfigChanged 'Fresh profile was not configured'
    $commands = (Read-Config).CommandList
    Assert ($commands.Count -eq 2) 'Expected two commands'
    $begin = $commands[0].Details
    $end = $commands[1].Details
    Assert ($begin.Utterance -ceq 'begin dictation' -and $end.Utterance -ceq 'end dictation') 'Wrong phrases'
    Assert (($begin.Actions.intent -join ',') -ceq 'Task.CustomCommand.KeyPress,Task.Command.Mode,Task.CustomCommand.KeyPress') 'Wrong begin order'
    Assert (($end.Actions.intent -join ',') -ceq 'Task.CustomCommand.KeyPress,Task.Command.Mode,Task.CustomCommand.KeyPress,Task.OpenFilePath,Task.Default.Mode') 'Wrong end order'
    Assert ($begin.Actions[0].entities[0].entity -ceq '{{ctrl}}{{alt}}{{shift}}{f9}' -and $end.Actions[2].entities[0].entity -ceq '{{ctrl}}{{alt}}{{shift}}{f10}') 'Wrong memory hotkeys'
    Assert ($begin.Actions[2].entities[0].entity -ceq '{{ctrl}}{{Windows}}{space}' -and $end.Actions[0].entities[0].entity -ceq '{{ctrl}}{{Windows}}{space}') 'Wrong Flow toggle'
    $folder = Split-Path -Parent $result.Executable
    Assert ($end.Actions[3].entities[0].entity -eq (Join-Path $folder 'Return to default.lnk')) 'Wrong profile path'
    $shell = New-Object -ComObject WScript.Shell
    $action = $shell.CreateShortcut((Join-Path $folder 'Default action.lnk'))
    $startup = $shell.CreateShortcut($result.StartupShortcut)
    Assert ($action.TargetPath -eq $result.Executable -and $action.Arguments -eq 'action') 'Wrong action shortcut'
    Assert ($startup.TargetPath -eq $result.Executable -and !$startup.Arguments) 'Wrong login shortcut'
    $manifest = Get-Content -Raw (Join-Path $root 'release.json') | ConvertFrom-Json
    Assert ((Get-FileHash $result.Executable).Hash -eq $manifest.sha256) 'Wrong executable'
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($result.Executable)
    Assert ($info.ProductVersion -ceq $manifest.version -and $info.FileVersion -ceq "$($manifest.version).0") 'Wrong Windows version information'
    Assert ((Get-FileHash (Join-Path $folder 'LICENSE')).Hash -eq (Get-FileHash (Join-Path $root 'LICENSE')).Hash) 'Wrong license'
    $before = [IO.File]::ReadAllText($config)
    $repeat = Run-Setup
    Assert (!$repeat.ConfigChanged -and [IO.File]::ReadAllText($config) -ceq $before) 'Reinstall changed existing commands'
    if ($ExerciseProcess) {
        Assert (@(Get-Process VoiceModeMemory | Where-Object Path -eq $result.Executable).Count -eq 1) 'Expected one active listener'
    }
    $removed = & $installer -ProfileRoot $profile -Uninstall
    Assert ($removed.ConfigChanged -and (Read-Config).CommandList.Count -eq 0) 'Fresh uninstall left commands'
    Assert (!(Test-Path -LiteralPath $result.StartupShortcut) -and !(Test-Path -LiteralPath $result.Executable)) 'Uninstall left installed files'
    $before = '{"OtherSetting":"preserve","CommandList":[{"CustomIntent":"Example.Custom","Details":{"Utterance":"my shortcut"},"Extra":[1,2]}]}'
    [IO.File]::WriteAllText($config,$before,$utf8)
    $again = Run-Setup
    Assert ([IO.File]::ReadAllText($again.Backup) -ceq $before) 'Backup differs from the original'
    $doc = Read-Config
    Assert ($doc.OtherSetting -ceq 'preserve' -and $doc.CommandList[0].Extra[1] -eq 2) 'Existing data changed'
    $doc.CommandList += [pscustomobject]@{ CustomIntent='Later.Custom'; Details=@{ Utterance='added later' } }
    [IO.File]::WriteAllText($config,($doc | ConvertTo-Json -Depth 15),$utf8)
    $null = & $installer -ProfileRoot $profile -Uninstall
    Assert (((Read-Config).CommandList.CustomIntent -join ',') -ceq 'Example.Custom,Later.Custom') 'Uninstall removed unrelated edits'
    foreach ($invalid in @('{"CommandList":[{"CustomIntent":"Other.Begin","Details":{"Utterance":"begin dictation"}}]}','{"unexpected":true}','invalid JSON')) {
        [IO.File]::WriteAllText($config,$invalid,$utf8)
        $failed = $false
        try { $null = Run-Setup } catch { $failed = $true }
        Assert ($failed -and [IO.File]::ReadAllText($config) -ceq $invalid) 'Conflict or malformed configuration was overwritten'
        Assert (!(Test-Path -LiteralPath $result.StartupShortcut)) 'Failed setup registered a login item'
    }
    'Passed clean install, reinstall, backup, merge, conflict handling and uninstall.'
} finally {
    if ($ExerciseProcess -and $result) {
        Get-Process -Name VoiceModeMemory -ErrorAction SilentlyContinue | Where-Object Path -eq $result.Executable | Stop-Process
    }
    # This disposable profile is created with a fresh GUID directly under the system temp directory.
    $full = [IO.Path]::GetFullPath($profile)
    $parent = [IO.Path]::GetDirectoryName($full)
    if ($parent -eq [IO.Path]::GetTempPath().TrimEnd('\') -and [IO.Path]::GetFileName($full) -match '^wispr-mode-test-[0-9a-f-]{36}$' -and [IO.Directory]::Exists($full)) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
