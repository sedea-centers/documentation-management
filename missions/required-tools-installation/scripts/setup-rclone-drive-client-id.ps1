#Requires -Version 5.1
<#
.SYNOPSIS
  setup-rclone-drive-client-id.ps1 - Windows PowerShell port of setup-rclone-drive-client-id.sh

.DESCRIPTION
  Expects authenticated gcloud + a Drive-capable service-account JSON.
  Requires --gcloud-account (explicit user email); never mutates global active account.
  Ensures Internal OAuth consent, provisions an OAuth client for rclone Drive
  (https://rclone.org/drive/#making-your-own-client-id), and writes
  client_id / client_secret into rclone config.

  API note (2026): clientauthconfig.googleapis.com /v1/projects/{n}/brands returns
  HTTP 404. This script uses IAP OAuth Admin REST (iap.googleapis.com) which still
  creates Internal brands + clients suitable for rclone client_id/client_secret.
  Google has deprecated IAP OAuth Admin APIs (turn-down timeline on gcloud warnings);
  when those stop working, replace Ensure-InternalBrand / New-DesktopClient.

  Forbidden: printing client_secret or oauth-client.json contents to stdout/stderr.

  Exit codes: 0 ok | 1 usage | 2 preconditions | 3 GCP/oauth | 4 rclone

.NOTES
  Center script: missions/required-tools-installation/scripts/setup-rclone-drive-client-id.ps1
  Tracking: sedea-centers/documentation-management#72
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string] $ProjectId,

  [Parameter(Mandatory = $false)]
  [Alias('CredentialsPath')]
  [string] $CredentialsPathArg,

  [Parameter(Mandatory = $false)]
  [string] $RcloneRemote = 'sedea-gdrive',

  [Parameter(Mandatory = $false)]
  [string] $ClientDisplayName = 'sedea-rclone-drive',

  [Parameter(Mandatory = $false)]
  [string] $OauthStoreDir,

  [Parameter(Mandatory = $false)]
  [switch] $ReuseExistingOauth,

  [Parameter(Mandatory = $false)]
  [string] $SupportEmail,

  [Parameter(Mandatory = $false)]
  [switch] $DryRun,

  [Parameter(Mandatory = $false)]
  [string] $GcloudAccount,

  [Parameter(Mandatory = $false)]
  [switch] $Help,

  # Raw argv passthrough for bash-style --flags from skill invoke
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Remaining
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:CLOUDSDK_CORE_DISABLE_PROMPTS = if ($env:CLOUDSDK_CORE_DISABLE_PROMPTS) { $env:CLOUDSDK_CORE_DISABLE_PROMPTS } else { '1' }

function Write-Log {
  param([string] $Message)
  [Console]::Error.WriteLine($Message)
}

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory = $true)][string] $Path,
    [Parameter(Mandatory = $true)][string[]] $Lines
  )
  $text = ($Lines -join "`n") + "`n"
  $enc = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $text, $enc)
}

function Die {
  param(
    [int] $Code,
    [string] $Message
  )
  Write-Log "ERROR: $Message"
  exit $Code
}

# Safe stderr snip for IAP JSON errors — never echo secret / clientSecret fields.
function Format-SafeIapErrorSnip {
  param(
    [object] $JsonObject,
    [int] $MaxLen = 300
  )
  if ($null -eq $JsonObject) { return '{}' }
  try {
    $safe = [ordered]@{}
    $props = $JsonObject.PSObject.Properties
    foreach ($name in @('error', 'message', 'status', 'code', 'details')) {
      if ($props[$name]) { $safe[$name] = $JsonObject.$name }
    }
    $keys = @($props | ForEach-Object { $_.Name })
    if ($keys.Count -gt 0) { $safe['keys'] = $keys }
    # Explicitly omit secret-bearing fields even if present under other names.
    foreach ($secretKey in @('secret', 'clientSecret', 'client_secret', 'clientId', 'client_id', 'name')) {
      if ($safe.Contains($secretKey)) { $safe.Remove($secretKey) }
    }
    $snip = ($safe | ConvertTo-Json -Compress -Depth 4)
    if ($snip.Length -gt $MaxLen) { $snip = $snip.Substring(0, $MaxLen) }
    return $snip
  }
  catch {
    return '{redacted}'
  }
}

function Show-Usage {
  @"
Usage: setup-rclone-drive-client-id.ps1 --project-id <id> --credentials-path <sa.json> [options]

Required:
  --project-id <id>
  --credentials-path <path>   Absolute path to Drive-capable SA JSON
  --gcloud-account <email>    Google user account (explicit --account on every gcloud)

Options:
  --rclone-remote <name>         Default: sedea-gdrive
  --client-display-name <name>   Default: sedea-rclone-drive
  --oauth-store-dir <dir>        Default: `$HOME/.config/sedea/documentation-management
  --reuse-existing-oauth         Skip create when oauth-client.json already valid
  --support-email <email>        Default: --gcloud-account value
  --dry-run                      Plan only (no secrets printed)
  -h, --help
"@ | Write-Output
}

function Test-CommandOnPath {
  param([string] $Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-HomeDir {
  if ($env:USERPROFILE) { return $env:USERPROFILE }
  if ($env:HOME) { return $env:HOME }
  return [Environment]::GetFolderPath('UserProfile')
}

function Get-RcloneConfigPath {
  if ($env:RCLONE_CONFIG -and $env:RCLONE_CONFIG.Trim()) {
    return $env:RCLONE_CONFIG
  }
  # rclone Windows default: %APPDATA%\rclone\rclone.conf
  $appData = $env:APPDATA
  if (-not $appData) {
    $appData = Join-Path (Get-HomeDir) 'AppData\Roaming'
  }
  return (Join-Path $appData 'rclone\rclone.conf')
}

function Get-JsonFirstBrandName {
  param($JsonObject)
  if ($null -eq $JsonObject) { return '' }
  $props = $JsonObject.PSObject.Properties
  if ($props['brands']) {
    $b = $JsonObject.brands
    if ($b -is [System.Array] -and $b.Count -gt 0) {
      if ($b[0].PSObject.Properties['name']) { return [string]$b[0].name }
    }
    elseif ($b -and $b.PSObject.Properties['name']) {
      return [string]$b.name
    }
  }
  if ($props['name']) { return [string]$JsonObject.name }
  return ''
}

function Invoke-Gcloud {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $GcloudArgs,
    [switch] $AllowFail
  )
  if (-not $script:GCLOUD_ACCOUNT) {
    Die 2 '--gcloud-account is required'
  }
  $withAccount = @('--account', $script:GCLOUD_ACCOUNT) + $GcloudArgs
  # gcloud writes notices to stderr; with $ErrorActionPreference Stop those
  # ErrorRecords terminate before exit-code handling. Prefer gcloud.cmd on Windows
  # (avoids gcloud.ps1 execution-policy / stderr wrapping issues).
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $gcloudCmd = Get-Command gcloud.cmd -ErrorAction SilentlyContinue
    if ($gcloudCmd) {
      $out = & $gcloudCmd.Source @withAccount 2>&1
    } else {
      $out = & gcloud @withAccount 2>&1
    }
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prevEap
  }
  $stdout = New-Object System.Collections.Generic.List[string]
  $stderr = New-Object System.Collections.Generic.List[string]
  foreach ($line in @($out)) {
    if ($line -is [System.Management.Automation.ErrorRecord]) {
      [void]$stderr.Add($line.ToString())
    } else {
      [void]$stdout.Add([string]$line)
    }
  }
  $text = ($stdout -join "`n").Trim()
  $errText = ($stderr -join "`n").Trim()
  if (-not $AllowFail -and $code -ne 0) {
    $combined = if ($errText) { "$text`n$errText" } else { $text }
    $combined = $combined.Trim()
    if ($combined.Length -gt 400) { $combined = $combined.Substring(0, 400) }
    Die 3 "gcloud $($withAccount -join ' ') failed (exit $code): $combined"
  }
  return $text
}

function Invoke-IapRest {
  param(
    [Parameter(Mandatory = $true)][string] $Method,
    [Parameter(Mandatory = $true)][string] $Uri,
    [Parameter(Mandatory = $true)][string] $AccessToken,
    [Parameter(Mandatory = $true)][string] $ProjectIdLocal,
    [string] $Body = $null
  )
  $headers = @{
    Authorization         = "Bearer $AccessToken"
    'x-goog-user-project' = $ProjectIdLocal
  }
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    # [string]$Body=$null becomes "" in PowerShell — never send a body on GET.
    if (-not [string]::IsNullOrEmpty($Body)) {
      $resp = Invoke-WebRequest -Method $Method -Uri $Uri -Headers $headers -ContentType 'application/json' -Body $Body -UseBasicParsing
    } else {
      $resp = Invoke-WebRequest -Method $Method -Uri $Uri -Headers $headers -UseBasicParsing
    }
    if ([string]::IsNullOrWhiteSpace($resp.Content)) { return $null }
    try { return ($resp.Content | ConvertFrom-Json) } catch { return $null }
  }
  catch {
    $raw = $null
    $status = $null
    $exMsg = $_.Exception.Message
    try {
      $http = $_.Exception.Response
      if ($http) {
        $status = [int]$http.StatusCode
        $stream = $http.GetResponseStream()
        if ($stream) {
          $reader = New-Object System.IO.StreamReader($stream)
          $raw = $reader.ReadToEnd()
          $reader.Close()
        }
      }
    } catch { }
    if (-not $raw -and $null -ne $_.ErrorDetails -and $_.ErrorDetails.PSObject.Properties['Message']) {
      $raw = $_.ErrorDetails.Message
    }
    if (-not $raw) {
      return $null
    }
    if ($raw) {
      try {
        $parsed = $raw | ConvertFrom-Json
        # Attach HTTP status for callers (e.g. 409 ALREADY_EXISTS).
        if ($null -ne $status) {
          $parsed | Add-Member -NotePropertyName '_httpStatus' -NotePropertyValue $status -Force
        }
        return $parsed
      } catch {
        return $null
      }
    }
    return $null
  }
  finally {
    $ErrorActionPreference = $prevEap
  }
}

function Test-OauthStoreValid {
  param([string] $Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    return ([string]$obj.client_id).Length -gt 0 -and ([string]$obj.client_secret).Length -gt 0
  }
  catch {
    return $false
  }
}

function Read-OauthStore {
  param([string] $Path)
  $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  return @{
    ClientId     = [string]$obj.client_id
    ClientSecret = [string]$obj.client_secret
  }
}

function Write-OauthStore {
  param(
    [string] $Path,
    [string] $ClientId,
    [string] $ClientSecret,
    [string] $ProjectIdLocal
  )
  $payload = @{
    client_id     = $ClientId
    client_secret = $ClientSecret
    project_id    = $ProjectIdLocal
  } | ConvertTo-Json -Compress
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  Write-Utf8NoBomFile -Path $Path -Lines @($payload)
  try {
    $acl = Get-Acl -LiteralPath $Path
    # Best-effort tighten on NTFS; ignore failures on unusual FS.
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
      [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
      'FullControl',
      'Allow'
    )
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
  }
  catch { }
}

function Ensure-InternalBrand {
  param(
    [string] $AccessToken,
    [string] $ProjectIdLocal,
    [string] $SupportEmailLocal
  )
  $listUri = "https://iap.googleapis.com/v1/projects/${ProjectIdLocal}/brands"
  $listJson = Invoke-IapRest -Method GET -Uri $listUri -AccessToken $AccessToken -ProjectIdLocal $ProjectIdLocal
  $brandName = Get-JsonFirstBrandName -JsonObject $listJson

  if ($brandName) {
    Write-Log 'oauth brand exists (iap)'
    $patchUri = "https://iap.googleapis.com/v1/${brandName}?updateMask=orgInternalOnly"
    $null = Invoke-IapRest -Method PATCH -Uri $patchUri -AccessToken $AccessToken -ProjectIdLocal $ProjectIdLocal -Body '{"orgInternalOnly": true}'
    return $brandName
  }

  Write-Log 'creating OAuth consent brand via iap.googleapis.com (Internal) ...'
  $createBody = @{
    applicationTitle = 'Sedea rclone Drive'
    supportEmail     = $SupportEmailLocal
  } | ConvertTo-Json -Compress
  $createJson = Invoke-IapRest -Method POST -Uri $listUri -AccessToken $AccessToken -ProjectIdLocal $ProjectIdLocal -Body $createBody
  $brandName = Get-JsonFirstBrandName -JsonObject $createJson
  if (-not $brandName -and $createJson -and $createJson.PSObject.Properties['name']) {
    $brandName = [string]$createJson.name
  }
  # Create may 409 ALREADY_EXISTS when brand appeared between list and create.
  if (-not $brandName) {
    $listJson = Invoke-IapRest -Method GET -Uri $listUri -AccessToken $AccessToken -ProjectIdLocal $ProjectIdLocal
    $brandName = Get-JsonFirstBrandName -JsonObject $listJson
  }
  if (-not $brandName) {
    $snip = Format-SafeIapErrorSnip -JsonObject $createJson -MaxLen 200
    Die 3 "failed to create or locate OAuth consent brand via iap.googleapis.com: $snip"
  }
  return $brandName
}

function New-DesktopClient {
  param(
    [string] $BrandName,
    [string] $AccessToken,
    [string] $ProjectIdLocal,
    [string] $DisplayName,
    [string] $OauthJsonPath
  )
  if (-not $BrandName) { Die 3 'create_desktop_client: missing brand' }
  Write-Log "creating OAuth client via iap.googleapis.com (displayName=${DisplayName}) ..."
  $uri = "https://iap.googleapis.com/v1/${BrandName}/identityAwareProxyClients"
  $body = @{ displayName = $DisplayName } | ConvertTo-Json -Compress
  $resp = Invoke-IapRest -Method POST -Uri $uri -AccessToken $AccessToken -ProjectIdLocal $ProjectIdLocal -Body $body

  $cid = ''
  $sec = ''
  $name = ''
  if ($resp) {
    $rp = $resp.PSObject.Properties
    if ($rp['clientId']) { $cid = [string]$resp.clientId }
    elseif ($rp['client_id']) { $cid = [string]$resp.client_id }
    if ($rp['name']) { $name = [string]$resp.name }
    if (-not $cid -and $name -like '*identityAwareProxyClients/*') {
      $cid = ($name -split '/')[-1]
    }
    if ($rp['secret']) { $sec = [string]$resp.secret }
    elseif ($rp['clientSecret']) { $sec = [string]$resp.clientSecret }
    elseif ($rp['client_secret']) { $sec = [string]$resp.client_secret }
  }

  if (-not $cid -or -not $sec) {
    $errSnip = Format-SafeIapErrorSnip -JsonObject $resp -MaxLen 300
    Die 3 ('IAP OAuth client create failed - ' + $errSnip + '. Need iap.identityAwareProxyClients.create (and brands). Do not paste secrets into chat. Fix IAM and re-run.')
  }

  Write-OauthStore -Path $OauthJsonPath -ClientId $cid -ClientSecret $sec -ProjectIdLocal $ProjectIdLocal
  $cidLen = $cid.Length
  Write-Log ('OAuth client stored (client_id length=' + $cidLen + ' - secret not logged)')
}

function Write-RcloneRemote {
  param(
    [string] $ClientId,
    [string] $ClientSecret,
    [string] $RemoteName
  )
  $confPath = Get-RcloneConfigPath
  $confDir = Split-Path -Parent $confPath
  if (-not (Test-Path -LiteralPath $confDir)) {
    New-Item -ItemType Directory -Path $confDir -Force | Out-Null
  }
  $tmpPath = "$confPath.tmp.$PID"
  $sectionHeader = "[$RemoteName]"
  $newBlock = @(
    $sectionHeader
    'type = drive'
    'scope = drive'
    "client_id = $ClientId"
    "client_secret = $ClientSecret"
  )

  if ((Test-Path -LiteralPath $confPath) -and (Select-String -LiteralPath $confPath -Pattern "^\[$([regex]::Escape($RemoteName))\]" -Quiet)) {
    $lines = Get-Content -LiteralPath $confPath
    $out = New-Object System.Collections.Generic.List[string]
    $inSec = $false
    $done = $false
    foreach ($line in $lines) {
      if ($line -match '^\[') {
        if ($inSec -and -not $done) {
          $out.Add('type = drive')
          $out.Add('scope = drive')
          $out.Add("client_id = $ClientId")
          $out.Add("client_secret = $ClientSecret")
          $done = $true
        }
        $inSec = ($line -eq $sectionHeader)
        $out.Add($line)
        continue
      }
      if ($inSec -and ($line -match '^(type|scope|client_id|client_secret) =')) {
        continue
      }
      $out.Add($line)
    }
    if ($inSec -and -not $done) {
      $out.Add('type = drive')
      $out.Add('scope = drive')
      $out.Add("client_id = $ClientId")
      $out.Add("client_secret = $ClientSecret")
    }
    Write-Utf8NoBomFile -Path $tmpPath -Lines @($out.ToArray())
  }
  else {
    $existing = @()
    if (Test-Path -LiteralPath $confPath) {
      $existing = Get-Content -LiteralPath $confPath
    }
    $combined = @($existing) + $newBlock
    Write-Utf8NoBomFile -Path $tmpPath -Lines $combined
  }

  Move-Item -LiteralPath $tmpPath -Destination $confPath -Force
  try {
    $acl = Get-Acl -LiteralPath $confPath
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
      [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
      'FullControl',
      'Allow'
    )
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $confPath -AclObject $acl
  }
  catch { }
}

function Test-RcloneClientId {
  param([string] $RemoteName)
  $dump = & rclone config dump 2>$null
  if ($LASTEXITCODE -ne 0) {
    Die 4 'rclone config dump failed after write'
  }
  try {
    $obj = $dump | ConvertFrom-Json
  }
  catch {
    Die 4 'rclone config dump was not valid JSON'
  }
  $cid = $null
  if ($obj.PSObject.Properties.Name -contains $RemoteName) {
    $cid = $obj.$RemoteName.client_id
  }
  elseif ($obj.PSObject.Properties.Name -contains ($RemoteName + ':')) {
    $prop = $RemoteName + ':'
    $cid = $obj.$prop.client_id
  }
  if (-not $cid) {
    Die 4 'rclone remote missing non-empty client_id after write'
  }
}

# --- bash-style argv merge (skill invokes with --project-id style) ---
$argv = New-Object System.Collections.Generic.List[string]
if ($Remaining) { foreach ($r in $Remaining) { [void]$argv.Add($r) } }

# Also honor named params when called PowerShell-natively
$PROJECT_ID = $ProjectId
$CREDENTIALS_PATH = $CredentialsPathArg
$script:GCLOUD_ACCOUNT = $GcloudAccount
$RCLONE_REMOTE = $RcloneRemote
$CLIENT_DISPLAY_NAME = $ClientDisplayName
$OAUTH_STORE_DIR = $OauthStoreDir
$REUSE_EXISTING = [bool]$ReuseExistingOauth
$SUPPORT_EMAIL = $SupportEmail
$DRY_RUN = [bool]$DryRun

$i = 0
while ($i -lt $argv.Count) {
  $a = $argv[$i]
  switch -Regex ($a) {
    '^--project-id$' {
      if ($i + 1 -ge $argv.Count) { Die 1 '--project-id requires a value' }
      $PROJECT_ID = $argv[$i + 1]; $i += 2; continue
    }
    '^--credentials-path$' {
      if ($i + 1 -ge $argv.Count) { Die 1 '--credentials-path requires a value' }
      $CREDENTIALS_PATH = $argv[$i + 1]; $i += 2; continue
    }
    '^--gcloud-account$' {
      if ($i + 1 -ge $argv.Count) { Die 1 '--gcloud-account requires a value' }
      $script:GCLOUD_ACCOUNT = $argv[$i + 1]; $i += 2; continue
    }
    '^--rclone-remote$' {
      if ($i + 1 -ge $argv.Count) { Die 1 '--rclone-remote requires a value' }
      $RCLONE_REMOTE = $argv[$i + 1]; $i += 2; continue
    }
    '^--client-display-name$' {
      if ($i + 1 -ge $argv.Count) { Die 1 '--client-display-name requires a value' }
      $CLIENT_DISPLAY_NAME = $argv[$i + 1]; $i += 2; continue
    }
    '^--oauth-store-dir$' {
      if ($i + 1 -ge $argv.Count) { Die 1 '--oauth-store-dir requires a value' }
      $OAUTH_STORE_DIR = $argv[$i + 1]; $i += 2; continue
    }
    '^--support-email$' {
      if ($i + 1 -ge $argv.Count) { Die 1 '--support-email requires a value' }
      $SUPPORT_EMAIL = $argv[$i + 1]; $i += 2; continue
    }
    '^--reuse-existing-oauth$' { $REUSE_EXISTING = $true; $i += 1; continue }
    '^--dry-run$' { $DRY_RUN = $true; $i += 1; continue }
    '^(-h|--help)$' { Show-Usage; exit 0 }
    default {
      Show-Usage
      Die 1 "unknown argument: $a"
    }
  }
}

if ($Help) { Show-Usage; exit 0 }

if (-not $OAUTH_STORE_DIR) {
  $OAUTH_STORE_DIR = Join-Path (Get-HomeDir) '.config\sedea\documentation-management'
}

if (-not $PROJECT_ID) { Show-Usage; Die 1 '--project-id is required' }
if (-not $CREDENTIALS_PATH) { Show-Usage; Die 1 '--credentials-path is required' }
if (-not $script:GCLOUD_ACCOUNT) { Show-Usage; Die 1 '--gcloud-account is required' }
if (-not $RCLONE_REMOTE) { Die 1 '--rclone-remote must be non-empty' }

if (-not (Test-CommandOnPath 'gcloud')) { Die 2 'missing required command: gcloud' }
if (-not (Test-CommandOnPath 'rclone')) { Die 2 'missing required command: rclone' }

if (-not (Test-Path -LiteralPath $CREDENTIALS_PATH)) {
  Die 2 "credentials file not found: $CREDENTIALS_PATH"
}

$listedAccounts = Invoke-Gcloud -GcloudArgs @('auth', 'list', '--format=value(account)') -AllowFail
$accountListed = @($listedAccounts -split "`r?`n" | Where-Object { $_.Trim() -eq $script:GCLOUD_ACCOUNT })
if ($accountListed.Count -eq 0) {
  Die 2 "gcloud account not logged in: $($script:GCLOUD_ACCOUNT) - run gcloud auth login in the user terminal"
}

if (-not $SUPPORT_EMAIL) { $SUPPORT_EMAIL = $script:GCLOUD_ACCOUNT }

try {
  $saObj = Get-Content -LiteralPath $CREDENTIALS_PATH -Raw | ConvertFrom-Json
}
catch {
  Die 2 'credentials path is not usable JSON'
}
if ([string]$saObj.type -ne 'service_account') {
  Die 2 'credentials path is not a usable service-account JSON (type must be service_account)'
}
$SA_EMAIL = [string]$saObj.client_email
if (-not $SA_EMAIL) {
  Die 2 'credentials path is not a usable service-account JSON (missing client_email)'
}

Write-Log "preconditions ok: gcloud=$($script:GCLOUD_ACCOUNT) sa=${SA_EMAIL} project=${PROJECT_ID}"

$OAUTH_JSON = Join-Path $OAUTH_STORE_DIR 'oauth-client.json'
if (-not (Test-Path -LiteralPath $OAUTH_STORE_DIR)) {
  New-Item -ItemType Directory -Path $OAUTH_STORE_DIR -Force | Out-Null
}

if ($DRY_RUN) {
  Write-Log "dry-run: enable drive.googleapis.com + iap.googleapis.com on ${PROJECT_ID}"
  Write-Log "dry-run: ensure Internal OAuth brand via iap.googleapis.com (support=${SUPPORT_EMAIL})"
  Write-Log "dry-run: create/reuse OAuth client displayName=${CLIENT_DISPLAY_NAME}"
  Write-Log "dry-run: write client fields into rclone remote=${RCLONE_REMOTE} (secrets not printed)"
  Write-Log "dry-run: oauth store=${OAUTH_JSON}"
  exit 0
}

Write-Log 'enabling drive.googleapis.com and iap.googleapis.com ...'
$null = Invoke-Gcloud -GcloudArgs @('services', 'enable', 'drive.googleapis.com', 'iap.googleapis.com', "--project=$PROJECT_ID")

$PROJECT_NUMBER = Invoke-Gcloud -GcloudArgs @('projects', 'describe', $PROJECT_ID, '--format=value(projectNumber)')
if (-not $PROJECT_NUMBER) { Die 3 "could not resolve projectNumber for ${PROJECT_ID}" }

$ACCESS_TOKEN = Invoke-Gcloud -GcloudArgs @('auth', 'print-access-token')
if (-not $ACCESS_TOKEN) { Die 2 'gcloud auth print-access-token failed' }

if ($REUSE_EXISTING) {
  if (-not (Test-OauthStoreValid -Path $OAUTH_JSON)) {
    Die 2 "--reuse-existing-oauth set but oauth store missing/invalid: ${OAUTH_JSON}"
  }
  Write-Log 'reusing existing oauth store'
}
elseif (Test-OauthStoreValid -Path $OAUTH_JSON) {
  Write-Log "oauth store already present - reusing (delete ${OAUTH_JSON} to force recreate)"
}
else {
  $BRAND_NAME = Ensure-InternalBrand -AccessToken $ACCESS_TOKEN -ProjectIdLocal $PROJECT_ID -SupportEmailLocal $SUPPORT_EMAIL
  if (-not $BRAND_NAME) { Die 3 'OAuth consent brand unavailable' }
  New-DesktopClient -BrandName $BRAND_NAME -AccessToken $ACCESS_TOKEN -ProjectIdLocal $PROJECT_ID -DisplayName $CLIENT_DISPLAY_NAME -OauthJsonPath $OAUTH_JSON
}

if (-not (Test-OauthStoreValid -Path $OAUTH_JSON)) {
  Die 3 "oauth store invalid after provision: ${OAUTH_JSON}"
}

$oauth = Read-OauthStore -Path $OAUTH_JSON
$CLIENT_ID = $oauth.ClientId
$CLIENT_SECRET = $oauth.ClientSecret
if (-not $CLIENT_ID -or -not $CLIENT_SECRET) {
  Die 3 'oauth store incomplete'
}

Write-Log ('writing rclone remote ' + $RCLONE_REMOTE + ' (non-interactive, secrets not printed) ...')
Write-RcloneRemote -ClientId $CLIENT_ID -ClientSecret $CLIENT_SECRET -RemoteName $RCLONE_REMOTE
Test-RcloneClientId -RemoteName $RCLONE_REMOTE

$CLIENT_SECRET = $null
$oauth = $null

Write-Log ('success: rclone remote ' + $RCLONE_REMOTE + ' has client_id; oauth store=' + $OAUTH_JSON)
Write-Log ('next: user runs rclone config reconnect ' + $RCLONE_REMOTE + ': in their terminal (browser OAuth)')
Write-Output 'rcloneClientConfigured=true'
Write-Output ('rcloneRemote=' + $RCLONE_REMOTE)
Write-Output ('oauthStorePath=' + $OAUTH_JSON)
Write-Output ('projectId=' + $PROJECT_ID)
Write-Output ('serviceAccountEmail=' + $SA_EMAIL)
exit 0
