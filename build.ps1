[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot 'out'),
    [switch] $Development
)
$ErrorActionPreference = 'Stop'
$name = 'VoiceModeMemory.exe'
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$compiler = Join-Path $framework 'csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw "Windows .NET Framework 4.x compiler missing at $compiler" }
$source = Join-Path $PSScriptRoot 'src\VoiceModeMemory.cs'
$release = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'release.json') | ConvertFrom-Json
$version = [version]$release.version
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('voice-mode-memory-build-' + [guid]::NewGuid())
$staged = Join-Path $temporary $name
$versionSource = Join-Path $temporary 'AssemblyVersion.cs'
[void][IO.Directory]::CreateDirectory($temporary)
try {
    [IO.File]::WriteAllLines($versionSource, @(
        'using System.Reflection;'
        "[assembly: AssemblyVersion(`"$version.0`")]"
        "[assembly: AssemblyFileVersion(`"$version.0`")]"
        "[assembly: AssemblyInformationalVersion(`"$version`")]"
    ))
    $messages = & $compiler /nologo /target:winexe /optimize+ /platform:x64 /r:System.Drawing.dll /r:System.Windows.Forms.dll "/out:$staged" $source $versionSource
    if ($LASTEXITCODE -ne 0) { throw "C# compiler failed. $($messages -join [Environment]::NewLine)" }
    if (!$Development) {
        $bytes = [IO.File]::ReadAllBytes($staged)
        # Framework csc assigns the COFF timestamp and a fresh MVID on every invocation.
        $pe = [BitConverter]::ToInt32($bytes, 0x3c)
        if ([BitConverter]::ToUInt32($bytes, $pe) -ne 0x4550) { throw 'Invalid PE signature.' }
        $mvid = [Reflection.Assembly]::Load($bytes).ManifestModule.ModuleVersionId.ToByteArray()
        $offset = -1
        for ($i = 0; $i -le $bytes.Length - $mvid.Length; $i++) {
            if ($bytes[$i] -ne $mvid[0]) { continue }
            $j = 1
            while ($j -lt $mvid.Length -and $bytes[$i + $j] -eq $mvid[$j]) { $j++ }
            if ($j -eq $mvid.Length) {
                if ($offset -ne -1) { throw 'Ambiguous module ID location.' }
                $offset = $i
            }
        }
        if ($offset -eq -1) { throw 'Module ID not found.' }
        ([guid]$release.moduleVersionId).ToByteArray().CopyTo($bytes, $offset)
        [BitConverter]::GetBytes([uint32]$release.peTimestamp).CopyTo($bytes, $pe + 8)
        [IO.File]::WriteAllBytes($staged, $bytes)
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $staged).Hash
        if ($actual -ne $release.sha256) {
            throw "Release build hash mismatch. Expected $($release.sha256), got $actual. Use -Development for modified source."
        }
    }
    $output = [IO.Directory]::CreateDirectory($OutputDirectory).FullName
    $destination = Join-Path $output $name
    [IO.File]::Copy($staged, $destination, $true)
    Get-Item -LiteralPath $destination
} finally {
    [IO.File]::Delete($versionSource)
    if ([IO.File]::Exists($staged)) { [IO.File]::Delete($staged) }
    [IO.Directory]::Delete($temporary)
}
