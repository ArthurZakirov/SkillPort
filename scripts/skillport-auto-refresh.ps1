[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$MaximumLogBytes = 131072

function Stop-WithMessage {
    param([string]$Message)
    [Console]::Error.WriteLine("skillport-auto-refresh: $Message")
    exit 2
}

if (-not [IO.Path]::IsPathRooted($ConfigPath) -or -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Stop-WithMessage 'the machine config must be an existing absolute path'
}

try {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Stop-WithMessage 'the machine config is invalid JSON'
}

$RequiredEnvironment = @(
    'SKILLPORT_ROOT',
    'PRIVATE_CONTEXT_ROOT',
    'SKILLPORT_STATE_DIR',
    'SKILLPORT_GIT_BIN',
    'SKILLPORT_NODE_BIN',
    'SKILLPORT_NPX_BIN',
    'SKILLPORT_PYTHON_BIN',
    'SKILLPORT_GH_BIN'
)

foreach ($Name in $RequiredEnvironment) {
    $Value = [string]$Config.Environment.$Name
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Stop-WithMessage "required machine variable $Name is unset"
    }
    if (-not [IO.Path]::IsPathRooted($Value)) {
        Stop-WithMessage "required machine variable $Name must be an absolute Windows path"
    }
    Set-Item -LiteralPath "Env:$Name" -Value $Value
}

$SkillPortRoot = $env:SKILLPORT_ROOT
$PrivateContextRoot = $env:PRIVATE_CONTEXT_ROOT
$StateDirectory = $env:SKILLPORT_STATE_DIR
$GitBin = $env:SKILLPORT_GIT_BIN
$NodeBin = $env:SKILLPORT_NODE_BIN
$NpxBin = $env:SKILLPORT_NPX_BIN
$PythonBin = $env:SKILLPORT_PYTHON_BIN
$GhBin = $env:SKILLPORT_GH_BIN
$RegistryPath = Join-Path $PrivateContextRoot 'skillport\repositories.json'
$GuidanceCommon = Join-Path $PrivateContextRoot 'agent-guidance\common.md'
$GuidanceOverlay = Join-Path $PrivateContextRoot 'agent-guidance\windows-wsl.md'

foreach ($Executable in @($GitBin, $NodeBin, $NpxBin, $PythonBin, $GhBin)) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        Stop-WithMessage 'a configured executable is unavailable'
    }
}
foreach ($RequiredFile in @(
    (Join-Path $SkillPortRoot 'scripts\bootstrap-agent-guidance.py'),
    $RegistryPath,
    $GuidanceCommon,
    $GuidanceOverlay
)) {
    if (-not (Test-Path -LiteralPath $RequiredFile -PathType Leaf)) {
        Stop-WithMessage 'a derived SkillPort input is unavailable'
    }
}

[IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
$LogPath = Join-Path $StateDirectory 'refresh.log'
$LockPath = Join-Path $StateDirectory 'refresh.lock'
$RunDirectory = Join-Path $StateDirectory ('.run-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($RunDirectory) | Out-Null
$LockStream = $null

function Write-Status {
    param([string]$Message)
    if ((Test-Path -LiteralPath $LogPath) -and (Get-Item -LiteralPath $LogPath).Length -ge $MaximumLogBytes) {
        $Tail = @(Get-Content -LiteralPath $LogPath -Tail 400)
        [IO.File]::WriteAllLines($LogPath, $Tail)
    }
    $Timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    [IO.File]::AppendAllText($LogPath, "$Timestamp $Message$([Environment]::NewLine)")
}

function Invoke-Captured {
    param(
        [string]$Label,
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$LogSuccess
    )
    $OutputPath = Join-Path $RunDirectory 'command.out'
    $ErrorPath = Join-Path $RunDirectory 'command.err'
    try {
        $Output = @(& $FilePath @Arguments 2> $ErrorPath)
        $Status = $LASTEXITCODE
    } catch {
        $Output = @()
        $Status = 127
    }
    [IO.File]::WriteAllText($OutputPath, '')
    [IO.File]::WriteAllText($ErrorPath, '')
    if ($Status -ne 0) {
        Write-Status "ERROR $Label failed status=$Status"
    } elseif ($LogSuccess) {
        Write-Status "$Label ok"
    }
    return [pscustomobject]@{ Status = $Status; Output = $Output }
}

function Get-RepoLabel {
    param([string]$Repository)
    return ((Split-Path -Leaf $Repository) -replace '[^A-Za-z0-9._-]', '')
}

function Test-GitRepository {
    param([string]$Repository)
    $Label = Get-RepoLabel $Repository
    if (-not (Test-Path -LiteralPath (Join-Path $Repository '.git'))) {
        Write-Status "ERROR repo=$Label checkout_missing"
        return $false
    }
    return $true
}

function Get-GitValue {
    param([string]$Repository, [string]$Label, [string[]]$Arguments)
    $Result = Invoke-Captured -Label $Label -FilePath $GitBin -Arguments (@('-C', $Repository) + $Arguments)
    return [pscustomobject]@{
        Success = ($Result.Status -eq 0)
        Value = (($Result.Output -join "`n").Trim())
    }
}

function Update-SafeRepository {
    param([string]$Repository)
    if (-not (Test-GitRepository $Repository)) { return }
    $Name = Get-RepoLabel $Repository
    $BranchResult = Get-GitValue $Repository "repo=$Name branch_check" @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if (-not $BranchResult.Success) { return }
    $UpstreamResult = Get-GitValue $Repository "repo=$Name upstream_check" @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}')
    if (-not $UpstreamResult.Success) { return }
    $Upstream = $UpstreamResult.Value
    $Fetch = Invoke-Captured -Label "repo=$Name fetch" -FilePath $GitBin -Arguments @('-C', $Repository, 'fetch', '--quiet') -LogSuccess
    if ($Fetch.Status -ne 0) { return }
    $RelationResult = Get-GitValue $Repository "repo=$Name relation_check" @('rev-list', '--left-right', '--count', "HEAD...$Upstream")
    if (-not $RelationResult.Success -or $RelationResult.Value -notmatch '^(\d+)\s+(\d+)$') {
        Write-Status "ERROR repo=$Name invalid_relation"
        return
    }
    $Ahead = [int]$Matches[1]
    $Behind = [int]$Matches[2]
    if ($Ahead -gt 0 -and $Behind -gt 0) {
        Write-Status "repo=$Name refresh_skipped divergent_checkout"
        return
    }
    if ($Behind -gt 0) {
        $DirtyResult = Get-GitValue $Repository "repo=$Name worktree_check" @('status', '--porcelain', '--untracked-files=normal')
        if (-not $DirtyResult.Success) { return }
        if ($DirtyResult.Value.Length -gt 0) {
            Write-Status "repo=$Name refresh_skipped dirty_worktree"
            return
        }
        $Merge = Invoke-Captured -Label "repo=$Name fast_forward" -FilePath $GitBin -Arguments @('-C', $Repository, 'merge', '--ff-only', '--quiet', $Upstream) -LogSuccess
        if ($Merge.Status -ne 0) { Write-Status "ERROR repo=$Name fast_forward_blocked" }
    } elseif ($Ahead -gt 0) {
        Write-Status "repo=$Name local_commits_pending"
    } else {
        Write-Status "repo=$Name current"
    }
}

function Get-RemoteVisibility {
    param([string]$Repository)
    $Name = Get-RepoLabel $Repository
    $PreviousPrompt = $env:GH_PROMPT_DISABLED
    $PreviousColor = $env:NO_COLOR
    try {
        $env:GH_PROMPT_DISABLED = '1'
        $env:NO_COLOR = '1'
        Push-Location -LiteralPath $Repository
        $Result = Invoke-Captured -Label "repo=$Name visibility_check" -FilePath $GhBin -Arguments @('repo', 'view', '--json', 'visibility', '--jq', '.visibility')
    } finally {
        Pop-Location
        $env:GH_PROMPT_DISABLED = $PreviousPrompt
        $env:NO_COLOR = $PreviousColor
    }
    if ($Result.Status -ne 0) {
        Write-Status "repo=$Name push_skipped visibility_unverified"
        return $null
    }
    $Visibility = ($Result.Output -join '').Trim()
    if ($Visibility -notin @('PUBLIC', 'PRIVATE')) {
        Write-Status "repo=$Name push_skipped visibility_unverified"
        return $null
    }
    return $Visibility
}

function Test-SecretMaterial {
    param([string]$Repository, [string]$Upstream)
    $Name = Get-RepoLabel $Repository
    $NamesResult = Get-GitValue $Repository "repo=$Name credential_path_scan" @('diff', '--name-only', "$Upstream..HEAD", '--', '.')
    $PatchResult = Get-GitValue $Repository "repo=$Name credential_content_scan" @('diff', '--no-ext-diff', "$Upstream..HEAD", '--', '.')
    if (-not $NamesResult.Success -or -not $PatchResult.Success) { return $false }
    $Names = $NamesResult.Value
    $Patch = (($PatchResult.Value -split "`n") | Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') }) -join "`n"
    $PathPattern = '(?im)(^|/)(\.env($|\.)|\.npmrc$|\.yarnrc(\.yml)?$|\.netrc$|id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$|.*(secret|credential|token).*)'
    $SecretPattern = '(?im)(-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|(^|[^A-Z0-9])(AKIA|ASIA)[A-Z0-9]{16}([^A-Z0-9]|$)|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(proj-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{16,}|(api[_-]?key|client[_-]?secret|password|passwd|access[_-]?token|refresh[_-]?token)\s*[:=]\s*["'']?[A-Za-z0-9_./+=-]{12,})'
    if ([regex]::IsMatch($Names, $PathPattern) -or [regex]::IsMatch($Patch, $SecretPattern)) {
        Write-Status "repo=$Name push_skipped credential_scan_failed"
        return $false
    }
    Write-Status "repo=$Name credential_scan_passed"
    return $true
}

function Test-PublicPersonalData {
    param([string]$Repository, [string]$Upstream)
    $Name = Get-RepoLabel $Repository
    $PatchResult = Get-GitValue $Repository "repo=$Name personal_data_scan" @('diff', '--no-ext-diff', "$Upstream..HEAD", '--', '.')
    if (-not $PatchResult.Success) { return $false }
    $Patch = (($PatchResult.Value -split "`n") | Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') }) -join "`n"
    $Pattern = '(?im)([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|\+?[0-9][0-9 ()/.-]{8,}[0-9]|(straße|strasse|street|road|avenue|weg|platz)\s+[0-9]+|DE[0-9]{20})'
    if ([regex]::IsMatch($Patch, $Pattern)) {
        Write-Status "repo=$Name push_skipped personal_data_review_required"
        return $false
    }
    Write-Status "repo=$Name personal_data_scan_passed"
    return $true
}

function Push-SafeRepository {
    param([string]$Repository, [string]$DeclaredVisibility, [string]$ApprovedHead = '')
    if (-not [IO.Path]::IsPathRooted($Repository) -or -not (Test-GitRepository $Repository)) { return }
    $Name = Get-RepoLabel $Repository
    $Visibility = Get-RemoteVisibility $Repository
    if ($null -eq $Visibility -or $Visibility -ne $DeclaredVisibility) {
        Write-Status "repo=$Name push_skipped visibility_mismatch"
        return
    }
    $DirtyResult = Get-GitValue $Repository "repo=$Name worktree_check" @('status', '--porcelain', '--untracked-files=normal')
    if (-not $DirtyResult.Success -or $DirtyResult.Value.Length -gt 0) {
        Write-Status "repo=$Name push_skipped dirty_worktree"
        return
    }
    $BranchResult = Get-GitValue $Repository "repo=$Name branch_check" @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if (-not $BranchResult.Success) { return }
    $UpstreamResult = Get-GitValue $Repository "repo=$Name upstream_check" @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}')
    if (-not $UpstreamResult.Success) { return }
    $Upstream = $UpstreamResult.Value
    $Fetch = Invoke-Captured -Label "repo=$Name push_fetch" -FilePath $GitBin -Arguments @('-C', $Repository, 'fetch', '--quiet') -LogSuccess
    if ($Fetch.Status -ne 0) { return }
    $RelationResult = Get-GitValue $Repository "repo=$Name push_relation_check" @('rev-list', '--left-right', '--count', "HEAD...$Upstream")
    if (-not $RelationResult.Success -or $RelationResult.Value -notmatch '^(\d+)\s+(\d+)$') { return }
    $Ahead = [int]$Matches[1]
    $Behind = [int]$Matches[2]
    if ($Ahead -eq 0) { Write-Status "repo=$Name push_skipped nothing_ahead"; return }
    if ($Behind -gt 0) { Write-Status "repo=$Name push_skipped behind_or_diverged"; return }
    if ($DeclaredVisibility -eq 'PUBLIC') {
        $HeadResult = Get-GitValue $Repository "repo=$Name head_check" @('rev-parse', 'HEAD')
        if (-not $HeadResult.Success -or $ApprovedHead -notmatch '^[0-9a-fA-F]{40}$' -or $HeadResult.Value -cne $ApprovedHead) {
            Write-Status "repo=$Name push_skipped public_release_review_required"
            return
        }
    }
    if (-not (Test-SecretMaterial $Repository $Upstream)) { return }
    if ($DeclaredVisibility -eq 'PUBLIC' -and -not (Test-PublicPersonalData $Repository $Upstream)) { return }
    Invoke-Captured -Label "repo=$Name ordinary_push" -FilePath $GitBin -Arguments @('-C', $Repository, 'push', '--quiet') -LogSuccess | Out-Null
}

function Read-RepositoryRegistry {
    try {
        $Registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
    } catch {
        throw 'the canonical repository registry is invalid JSON'
    }
    if ($Registry.version -ne 1 -or @($Registry.repositories).Count -eq 0) {
        throw 'the canonical repository registry is invalid'
    }
    return @($Registry.repositories)
}

function Resolve-RegistryCheckout {
    param($Entry)
    switch ([string]$Entry.checkout.kind) {
        'skillport-root' { return $SkillPortRoot }
        'private-context-root' { return $PrivateContextRoot }
        'skillport-sibling' {
            $Directory = [string]$Entry.checkout.directory
            if ($Directory -notmatch '^[A-Za-z0-9._-]+$') { throw 'the registry contains an unsafe checkout directory' }
            return Join-Path (Split-Path -Parent $SkillPortRoot) $Directory
        }
        'none' { return $null }
        default { throw 'the registry contains an unsupported checkout kind' }
    }
}

try {
    try {
        $LockStream = [IO.File]::Open($LockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
        exit 0
    }
    Write-Status 'refresh_start'
    Update-SafeRepository $SkillPortRoot
    if ($PrivateContextRoot -cne $SkillPortRoot) { Update-SafeRepository $PrivateContextRoot }
    $Repositories = Read-RepositoryRegistry
    foreach ($Entry in $Repositories) {
        if (-not [bool]$Entry.refresh) { continue }
        $Checkout = Resolve-RegistryCheckout $Entry
        if ($null -eq $Checkout -or $Checkout -ceq $SkillPortRoot -or $Checkout -ceq $PrivateContextRoot) { continue }
        $RegistryName = ([string]$Entry.name) -replace '[^A-Za-z0-9._-]', ''
        if (-not (Test-Path -LiteralPath (Join-Path $Checkout '.git'))) {
            Write-Status "repo=$RegistryName refresh_skipped checkout_missing"
            continue
        }
        Update-SafeRepository $Checkout
    }

    foreach ($Repository in @($Config.PushPrivateRepositories)) {
        Push-SafeRepository ([string]$Repository) 'PRIVATE'
    }
    foreach ($Entry in @($Config.PushPublicRepositories)) {
        Push-SafeRepository ([string]$Entry.Path) 'PUBLIC' ([string]$Entry.ApprovedHead)
    }

    $GuidanceResult = Invoke-Captured -Label 'global_guidance refresh' -FilePath $PythonBin -Arguments @((Join-Path $SkillPortRoot 'scripts\bootstrap-agent-guidance.py'), '--common', $GuidanceCommon, '--overlay', $GuidanceOverlay, '--platform', 'windows-wsl', '--registry', $RegistryPath) -LogSuccess
    if ($GuidanceResult.Status -ne 0) { exit 1 }

    foreach ($Entry in $Repositories) {
        if (-not [bool]$Entry.skills) { continue }
        $Source = [string]$Entry.source
        if ($Source -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'the registry contains an unsafe skill source' }
        $SyncResult = Invoke-Captured -Label 'global_skills synchronize' -FilePath $NpxBin -Arguments @('-y', 'skills', 'add', $Source, '--skill', '*', '-a', 'codex', '-g', '-y')
        if ($SyncResult.Status -ne 0) { exit 1 }
    }
    Write-Status 'global_skills synchronize ok'
    $Discovery = Invoke-Captured -Label 'global_skills discovery_check' -FilePath $NpxBin -Arguments @('-y', 'skills', 'ls', '-g', '-a', 'codex') -LogSuccess
    if ($Discovery.Status -ne 0) { exit 1 }
    foreach ($SkillName in @($Config.RequiredGlobalSkills)) {
        if ([string]$SkillName -notmatch '^[A-Za-z0-9._-]+$' -or -not (Test-Path -LiteralPath (Join-Path $HOME ".agents\skills\$SkillName\SKILL.md") -PathType Leaf)) {
            Write-Status 'ERROR global_skills required_skill_missing'
            exit 1
        }
    }
    Write-Status 'refresh_complete'
} catch {
    if ($null -ne $LockStream) { Write-Status 'ERROR refresh_failed status=1' }
    exit 1
} finally {
    if ($null -ne $LockStream) {
        $LockStream.Dispose()
        if (Test-Path -LiteralPath $LockPath) { Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $RunDirectory) { Remove-Item -LiteralPath $RunDirectory -Recurse -Force -ErrorAction SilentlyContinue }
}
