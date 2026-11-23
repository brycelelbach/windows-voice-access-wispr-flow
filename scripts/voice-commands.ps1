function New-FlowVoiceCommands([string]$Folder) {
    function KeyAction([string]$Keys) {
        [ordered]@{ intent = 'Task.CustomCommand.KeyPress'; entities = @(@{ entity = $Keys; type = 'Press.Keys' }) }
    }
    $toggle = KeyAction '{{ctrl}}{{Windows}}{space}'
    $commandMode = [ordered]@{ intent = 'Task.Command.Mode'; entities = @() }
    $begin = @((KeyAction '{{ctrl}}{{alt}}{{shift}}{f9}'), $commandMode, $toggle)
    $end = @($toggle, $commandMode, (KeyAction '{{ctrl}}{{alt}}{{shift}}{f10}'),
        @{ intent = 'Task.OpenFilePath'; entities = @(@{ entity = (Join-Path $Folder 'Return to default.lnk'); type = 'Path.File' }) },
        @{ intent = 'Task.Default.Mode'; entities = @() })
    foreach ($definition in @(
        @{ intent = 'Task.Customcommand.BeginDictate'; phrase = 'begin dictation'; actions = $begin },
        @{ intent = 'Task.Customcommand.EndDictate'; phrase = 'end dictation'; actions = $end }
    )) {
        [pscustomobject][ordered]@{
            CustomIntent = $definition.intent
            IsEnabled = $true
            CustomEntities = @()
            Details = [pscustomobject][ordered]@{
                Utterance = $definition.phrase; CustomCommandGroup = 'Wispr Flow'
                ApplicationName = ''; Actions = $definition.actions
            }
            Id = [guid]::NewGuid().ToString()
        }
    }
}

function Test-FlowCommand($Actual, $Expected) {
    if ($Actual.CustomIntent -cne $Expected.CustomIntent -or $Actual.Details.Utterance -ine $Expected.Details.Utterance -or
        $Actual.Details.CustomCommandGroup -cne 'Wispr Flow' -or $Actual.Details.ApplicationName -or
        $Actual.CustomEntities.Count -gt 0 -or !$Actual.Id -or $Actual.Details.Actions.Count -ne $Expected.Details.Actions.Count) { return $false }
    for ($i = 0; $i -lt $Expected.Details.Actions.Count; $i++) {
        $got = $Actual.Details.Actions[$i]
        $want = $Expected.Details.Actions[$i]
        if ($got.intent -cne $want.intent -or $got.entities.Count -ne $want.entities.Count) { return $false }
        if ($want.entities.Count -and ($got.entities[0].type -cne $want.entities[0].type -or
            $got.entities[0].entity -ine $want.entities[0].entity)) { return $false }
    }
    return $true
}

function Get-CommandUpdate([string]$Path, [string]$Folder, [bool]$Remove) {
    $original = $null
    $config = [pscustomobject]@{ CommandList = @() }
    if ([IO.File]::Exists($Path)) {
        $original = [IO.File]::ReadAllText($Path)
        $jsonOptions = @{}
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonOptions.DateKind = 'String' }
        $config = ConvertFrom-Json -InputObject $original @jsonOptions
        if ($config.CommandList -isnot [array]) { throw "Expected a CommandList array in $Path" }
    }
    $changed = $false
    foreach ($desired in (New-FlowVoiceCommands $Folder)) {
        $phrase = $desired.Details.Utterance
        $matches = @($config.CommandList | Where-Object { $_.CustomIntent -ieq $desired.CustomIntent -or $_.Details.Utterance -ieq $phrase })
        if ($matches.Count -gt 1 -or ($matches.Count -eq 1 -and !(Test-FlowCommand $matches[0] $desired))) {
            throw "An existing Voice Access shortcut conflicts with '$phrase'. Rename or export and remove that shortcut in Voice Access before retrying."
        }
        if ($Remove -and $matches.Count) {
            $config.CommandList = @($config.CommandList | Where-Object { $_.CustomIntent -cne $desired.CustomIntent })
            $changed = $true
        } elseif (!$Remove -and !$matches.Count) {
            $config.CommandList = @($config.CommandList) + $desired
            $changed = $true
        } elseif (!$Remove -and !$matches[0].IsEnabled) {
            throw "Enable the existing '$phrase' shortcut in Voice Access, then rerun the installer."
        }
    }
    [pscustomobject]@{ Original = $original; Config = $config; Changed = $changed }
}

function Save-CommandUpdate([string]$Path, $Update) {
    if (!$Update.Changed) { return }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $id = [guid]::NewGuid().ToString('N')
    $temp = "$Path.$id.tmp"
    try {
        $json = ConvertTo-Json -InputObject $Update.Config -Depth 100
        [IO.File]::WriteAllText($temp, $json, [Text.UTF8Encoding]::new($false))
        if ($null -eq $Update.Original) {
            [IO.File]::Move($temp, $Path)
            return
        }
        if ([IO.File]::ReadAllText($Path) -cne $Update.Original) { throw 'Voice shortcuts changed during setup. Retry the operation.' }
        $backup = "$Path.$(Get-Date -Format yyyyMMdd-HHmmss).$id.bak"
        [IO.File]::Replace($temp, $Path, $backup)
        return $backup
    } finally { [IO.File]::Delete($temp) }
}
