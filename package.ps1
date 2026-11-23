[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$app = & (Join-Path $PSScriptRoot 'build.ps1')
$zip = Join-Path $app.DirectoryName 'Windows.Voice.Access.Wispr.Flow.zip'
$items = @('README.md','LICENSE','install.ps1','build.ps1','package.ps1','release.json','scripts','src','tests') |
    ForEach-Object { Join-Path $PSScriptRoot $_ }
Compress-Archive -LiteralPath (@($app.FullName) + @($items)) -DestinationPath $zip -Force
Get-Item -LiteralPath $zip
