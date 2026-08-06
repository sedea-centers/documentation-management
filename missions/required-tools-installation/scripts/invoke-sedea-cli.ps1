#Requires -Version 5.1
<#
.SYNOPSIS
  Invoke the Sedea extension-management CLI on Windows.

.DESCRIPTION
  Stock %LOCALAPPDATA%\Programs\Sedea\bin\sedea.cmd fails on current Windows
  Sedea builds with ERR_UNSUPPORTED_ESM_URL_SCHEME (drive-letter path passed to
  Electron --import). This helper sets ELECTRON_RUN_AS_NODE and passes a
  file:// URL for nls.messages.js — the verified Windows workaround.

  Binding for documentation-management required-tools registry: use this script
  (or the equivalent inline recipe in rules/10_required-tools.mdc) for all
  Windows sedea-extension probe / install / dry-run steps. Do not call bare
  sedea.cmd until the product ships a fixed shim.

.PARAMETER SedeaRoot
  Optional absolute path to the Sedea application install root
  (directory that contains Sedea.exe). Default:
  $env:LOCALAPPDATA\Programs\Sedea
  Must be passed as a named parameter: -SedeaRoot <path>

.EXAMPLE
  .\invoke-sedea-cli.ps1 --list-extensions --show-versions

.EXAMPLE
  .\invoke-sedea-cli.ps1 --install-extension $env:TEMP\cweijan.vscode-office-4.1.7.vsix --force
#>
[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$SedeaRoot = $(Join-Path $env:LOCALAPPDATA 'Programs\Sedea'),

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CliArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $CliArgs -or $CliArgs.Count -eq 0) {
  Write-Error 'Pass Sedea CLI arguments after the script name (for example --list-extensions --show-versions).'
  exit 2
}

$exe = Join-Path $SedeaRoot 'Sedea.exe'
$nls = Join-Path $SedeaRoot 'resources\app\out\nls.messages.js'
$cliJs = Join-Path $SedeaRoot 'resources\app\out\cli.js'

foreach ($path in @($exe, $nls, $cliJs)) {
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Error "Sedea CLI prerequisite missing: $path (set -SedeaRoot if install is elsewhere)."
    exit 3
  }
}

$nlsUrl = ([Uri]$nls).AbsoluteUri
$env:ELECTRON_RUN_AS_NODE = '1'
if (Test-Path Env:VSCODE_DEV) {
  Remove-Item Env:VSCODE_DEV
}

# Start-Process so exit code is reliable under Set-StrictMode (native & does not
# always populate $LASTEXITCODE in this host).
$argList = @('--import', $nlsUrl, $cliJs) + @($CliArgs)
$proc = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru -NoNewWindow
exit $proc.ExitCode
