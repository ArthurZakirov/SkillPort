[CmdletBinding()]
param(
    [string[]]$PushPrivateRepository = @(),
    [string[]]$PushPublicRepository = @(),
    [string[]]$RequiredGlobalSkill = @(),
    [switch]$ReplaceExisting,
    [switch]$DryRun
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$TaskName = 'SkillPort Auto Refresh'

function Stop-WithMessage {
    param([string]$Message)
    throw "install-windows-auto-refresh: $Message"
}

if ($env:OS -ne 'Windows_NT') { Stop-WithMessage 'Windows is required' }
$SkillPortRoot = [string]$env:SKILLPORT_ROOT
$PrivateContextRoot = [string]$env:PRIVATE_CONTEXT_ROOT
foreach ($Entry in @{
    SKILLPORT_ROOT = $SkillPortRoot
    PRIVATE_CONTEXT_ROOT = $PrivateContextRoot
}.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace($Entry.Value)) { Stop-WithMessage "required environment variable $($Entry.Key) is unset" }
    if (-not [IO.Path]::IsPathRooted($Entry.Value)) { Stop-WithMessage "$($Entry.Key) must be an absolute Windows path" }
}

function Resolve-Executable {
    param([string]$EnvironmentName, [string[]]$CommandNames)
    $Configured = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if (-not [string]::IsNullOrWhiteSpace($Configured)) {
        if (-not [IO.Path]::IsPathRooted($Configured) -or -not (Test-Path -LiteralPath $Configured -PathType Leaf)) {
            Stop-WithMessage "$EnvironmentName must identify an existing absolute executable path"
        }
        return $Configured
    }
    foreach ($CommandName in $CommandNames) {
        $Command = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $Command) { return $Command.Source }
    }
    Stop-WithMessage "$EnvironmentName could not be discovered"
}

$GitBin = Resolve-Executable 'SKILLPORT_GIT_BIN' @('git.exe', 'git')
$NodeBin = Resolve-Executable 'SKILLPORT_NODE_BIN' @('node.exe', 'node')
$NpxBin = Resolve-Executable 'SKILLPORT_NPX_BIN' @('npx.cmd', 'npx')
$PythonBin = Resolve-Executable 'SKILLPORT_PYTHON_BIN' @('python.exe', 'python3.exe', 'python')
$GhBin = Resolve-Executable 'SKILLPORT_GH_BIN' @('gh.exe', 'gh')
$PowerShellBin = Resolve-Executable 'SKILLPORT_POWERSHELL_BIN' @('powershell.exe')

$StateDirectory = if ([string]::IsNullOrWhiteSpace($env:SKILLPORT_STATE_DIR)) {
    Join-Path $env:LOCALAPPDATA 'SkillPort'
} else { $env:SKILLPORT_STATE_DIR }
$ConfigPath = if ([string]::IsNullOrWhiteSpace($env:SKILLPORT_AUTO_REFRESH_CONFIG)) {
    Join-Path $StateDirectory 'auto-refresh.windows.json'
} else { $env:SKILLPORT_AUTO_REFRESH_CONFIG }
foreach ($PathEntry in @($StateDirectory, $ConfigPath)) {
    if (-not [IO.Path]::IsPathRooted($PathEntry)) { Stop-WithMessage 'state and config paths must be absolute' }
}

$RefreshScript = Join-Path $SkillPortRoot 'scripts\skillport-auto-refresh.ps1'
$RegistryPath = Join-Path $PrivateContextRoot 'skillport\repositories.json'
$GuidanceCommon = Join-Path $PrivateContextRoot 'agent-guidance\common.md'
$GuidanceOverlay = Join-Path $PrivateContextRoot 'agent-guidance\windows-wsl.md'
foreach ($RequiredPath in @($RefreshScript, $RegistryPath, $GuidanceCommon, $GuidanceOverlay)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) { Stop-WithMessage 'a derived SkillPort input is missing' }
}

foreach ($Repository in @($PushPrivateRepository) + @($PushPublicRepository)) {
    if (-not [IO.Path]::IsPathRooted($Repository) -or -not (Test-Path -LiteralPath (Join-Path $Repository '.git'))) {
        Stop-WithMessage 'each push repository must be an absolute Git checkout path'
    }
}
foreach ($SkillName in $RequiredGlobalSkill) {
    if ($SkillName -notmatch '^[A-Za-z0-9._-]+$') { Stop-WithMessage 'a required skill name is invalid' }
}

$MachineConfig = [ordered]@{
    Version = 1
    Environment = [ordered]@{
        SKILLPORT_ROOT = $SkillPortRoot
        PRIVATE_CONTEXT_ROOT = $PrivateContextRoot
        SKILLPORT_STATE_DIR = $StateDirectory
        SKILLPORT_GIT_BIN = $GitBin
        SKILLPORT_NODE_BIN = $NodeBin
        SKILLPORT_NPX_BIN = $NpxBin
        SKILLPORT_PYTHON_BIN = $PythonBin
        SKILLPORT_GH_BIN = $GhBin
    }
    PushPrivateRepositories = @($PushPrivateRepository)
    PushPublicRepositories = @($PushPublicRepository | ForEach-Object {
        [ordered]@{ Path = $_; ApprovedHead = 'REVIEW_REQUIRED' }
    })
    RequiredGlobalSkills = @($RequiredGlobalSkill)
}
$ConfigJson = $MachineConfig | ConvertTo-Json -Depth 5

if ($RefreshScript.Contains('"') -or $ConfigPath.Contains('"')) { Stop-WithMessage 'paths containing quote characters are unsupported' }
$ActionArguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$RefreshScript`" -ConfigPath `"$ConfigPath`""
$Escape = { param([string]$Value) [Security.SecurityElement]::Escape($Value) }
$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$UserSid = $CurrentIdentity.User.Value
$TaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Safely refresh canonical SkillPort sources and remote-installed skills.</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$(& $Escape $UserSid)</UserId></LogonTrigger>
    <CalendarTrigger>
      <StartBoundary>2000-01-01T00:00:00</StartBoundary><Enabled>true</Enabled>
      <Repetition><Interval>PT15M</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$(& $Escape $UserSid)</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit><Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author"><Exec><Command>$(& $Escape $PowerShellBin)</Command><Arguments>$(& $Escape $ActionArguments)</Arguments><WorkingDirectory>$(& $Escape $SkillPortRoot)</WorkingDirectory></Exec></Actions>
</Task>
"@

$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $ExistingTask -and -not $ReplaceExisting) { Stop-WithMessage 'the scheduled task already exists; reconcile it or use -ReplaceExisting' }
if ((Test-Path -LiteralPath $ConfigPath) -and -not $ReplaceExisting) { Stop-WithMessage 'the machine config already exists; reconcile it or use -ReplaceExisting' }

$GuidanceArguments = @(
    (Join-Path $SkillPortRoot 'scripts\bootstrap-agent-guidance.py'),
    '--common', $GuidanceCommon,
    '--overlay', $GuidanceOverlay,
    '--platform', 'windows-wsl',
    '--registry', $RegistryPath,
    '--dry-run'
)
if ($ReplaceExisting) { $GuidanceArguments += '--replace-existing' }
& $PythonBin @GuidanceArguments | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'layered guidance preflight failed' }

[Console]::WriteLine("Task: $TaskName")
[Console]::WriteLine('Triggers: current-user logon and daily quarter-hour repetition with StartWhenAvailable')
if ($DryRun) { exit 0 }

[IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
$DirectoryAcl = New-Object Security.AccessControl.DirectorySecurity
$DirectoryAcl.SetOwner($CurrentIdentity.User)
$DirectoryAcl.SetAccessRuleProtection($true, $false)
$DirectoryRule = New-Object Security.AccessControl.FileSystemAccessRule($CurrentIdentity.User, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$DirectoryAcl.AddAccessRule($DirectoryRule)
Set-Acl -LiteralPath $StateDirectory -AclObject $DirectoryAcl
[IO.File]::WriteAllText($ConfigPath, $ConfigJson, [Text.UTF8Encoding]::new($false))
$FileAcl = New-Object Security.AccessControl.FileSecurity
$FileAcl.SetOwner($CurrentIdentity.User)
$FileAcl.SetAccessRuleProtection($true, $false)
$FileRule = New-Object Security.AccessControl.FileSystemAccessRule($CurrentIdentity.User, 'FullControl', 'Allow')
$FileAcl.AddAccessRule($FileRule)
Set-Acl -LiteralPath $ConfigPath -AclObject $FileAcl

$GuidanceArguments = @(
    (Join-Path $SkillPortRoot 'scripts\bootstrap-agent-guidance.py'),
    '--common', $GuidanceCommon,
    '--overlay', $GuidanceOverlay,
    '--platform', 'windows-wsl',
    '--registry', $RegistryPath
)
if ($ReplaceExisting) { $GuidanceArguments += '--replace-existing' }
& $PythonBin @GuidanceArguments | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'layered guidance installation failed' }

Register-ScheduledTask -TaskName $TaskName -Xml $TaskXml -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
[Console]::WriteLine('Installed and started SkillPort Auto Refresh')
