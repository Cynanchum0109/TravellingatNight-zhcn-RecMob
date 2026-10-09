[CmdletBinding()]
param([string]$GameDir = "",
      # Set by the in-game updater plugin: a package it already downloaded,
      # no confirmation prompt, and the game's pid to wait out before touching
      # its files.
      [string]$Staged = "",
      [switch]$Yes,
      [int]$WaitForProcess = 0)

# The player-side updater. It reaches a player two ways: installed into the
# game folder by the patch itself (BepInEx/plugins/TravellingZh/updater.ps1),
# and published next to manifest.json, where the standalone 【双击更新】 .cmd
# fetches the current copy each time it runs - so that .cmd can sit on the
# desktop, never changes, and always runs today's logic.
#
# "The cloud" is a GitHub branch read through several mirrors ($UpdateBases,
# tried in order); when none of them answers, the player is pointed at the
# QQ group for a full package instead.
#
# Asks the cloud what the current patch version is, and if it is newer than
# what install_manifest.json says is installed, downloads the small update
# package, verifies it, and hands it to the normal installer for an in-place
# upgrade. The player never has to go find a download link again after the
# first full install.
#
# Nothing here is trusted from the network without a check: the manifest
# names a sha256 for the zip, and the installer inside the zip re-verifies
# every payload file against its own manifest before touching the game.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Rewritten by scripts/package_release.py at build time, like installer.ps1.
$PackageName     = "夜游漫记 Demo 简体中文补丁"
$StateFolderName = ".travellingzh_patch"
$UpdateBases     = "https://fastly.jsdelivr.net/gh/Cynanchum0109/TravellingatNight-zhcn-RecMob@update/travelling https://gcore.jsdelivr.net/gh/Cynanchum0109/TravellingatNight-zhcn-RecMob@update/travelling https://cdn.jsdelivr.net/gh/Cynanchum0109/TravellingatNight-zhcn-RecMob@update/travelling https://raw.githubusercontent.com/Cynanchum0109/TravellingatNight-zhcn-RecMob/update/travelling" -split ' '
$ManualHint      = "请到 QQ 群 815655398 或百度网盘 https://pan.baidu.com/s/1D6q_cTM8dgRdYSNepM7VBQ?pwd=ffoe（提取码 ffoe）下载最新完整包，直接覆盖安装即可。"

function Write-Stage([string]$Message) {
    Write-Host "`n== $Message ==" -ForegroundColor Cyan
}

function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "")
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Show-Popup([string]$Title, [string]$Message, [int]$Icon) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($Message, 0, $Title, $Icon)
    } catch {
        Write-Host $Message
    }
}

# Same discovery as installer.ps1: Steam's registry entry gives the main
# library, libraryfolders.vdf the extra drives. Duplicated rather than shared
# because this file has to stand alone when fetched from the cloud.
function Get-SteamLibraries {
    $libraries = @()
    foreach ($key in @("HKCU:\Software\Valve\Steam",
                       "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
                       "HKLM:\SOFTWARE\Valve\Steam")) {
        try {
            $steamPath = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).SteamPath
        } catch { continue }
        if ([string]::IsNullOrWhiteSpace($steamPath)) { continue }
        $steamPath = $steamPath -replace '/', '\'
        if ($libraries -notcontains $steamPath) { $libraries += $steamPath }
        $vdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
        if (-not (Test-Path -LiteralPath $vdf -PathType Leaf)) { continue }
        try { $text = Get-Content -LiteralPath $vdf -Raw -ErrorAction Stop } catch { continue }
        foreach ($m in [regex]::Matches($text, '"path"\s*"([^"]+)"')) {
            $lib = $m.Groups[1].Value -replace '\\\\', '\'
            if ($libraries -notcontains $lib) { $libraries += $lib }
        }
    }
    return $libraries
}

function Find-SteamGameRoot {
    foreach ($library in Get-SteamLibraries) {
        $common = Join-Path $library "steamapps\common"
        if (-not (Test-Path -LiteralPath $common -PathType Container)) { continue }
        $direct = Join-Path $common "Travelling at Night Demo"
        if (Test-Path -LiteralPath (Join-Path $direct "travelling.exe") -PathType Leaf) { return $direct }
        # The folder gets renamed when the demo becomes the full game, so fall
        # back to whichever folder actually holds the executable.
        try { $folders = Get-ChildItem -LiteralPath $common -Directory -ErrorAction Stop } catch { continue }
        foreach ($folder in $folders) {
            if (Test-Path -LiteralPath (Join-Path $folder.FullName "travelling.exe") -PathType Leaf) {
                return $folder.FullName
            }
        }
    }
    return $null
}

function Test-GameRoot([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    return Test-Path -LiteralPath (Join-Path $Dir.Trim('"') "travelling.exe") -PathType Leaf
}

Write-Host "$PackageName - 检查更新" -ForegroundColor Green

# Where the game is, from the most explicit hint down: a directory the caller
# named (the .cmd passes its own folder, which only counts when that folder is
# the game root), the game folder this file was installed into, then Steam's
# own records - so the .cmd works from the desktop too.
$GameRoot = $null
if (Test-GameRoot $GameDir) {
    $GameRoot = $GameDir.Trim('"')
} else {
    $installedInto = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (Test-GameRoot $installedInto) {
        $GameRoot = $installedInto
    } else {
        $GameRoot = Find-SteamGameRoot
        if ($GameRoot) { Write-Host "已通过 Steam 自动定位到游戏目录。" }
    }
}
if (-not $GameRoot) {
    throw "没有找到游戏目录。请把本文件放进游戏目录（Steam 里右键游戏 → 管理 → 浏览本地文件）再双击。"
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
Write-Host "游戏目录：$GameRoot"

$StateManifestPath = Join-Path $GameRoot "$StateFolderName\install_manifest.json"
if (-not (Test-Path -LiteralPath $StateManifestPath -PathType Leaf)) {
    throw "这台机器上还没装过汉化。更新器只能升级已经装好的汉化，请先下载完整包安装一次。"
}
$state = [IO.File]::ReadAllText($StateManifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$installedVersion = [string](Get-Prop $state "package_version")
Write-Host "已安装汉化版本：$installedVersion"

$localGameVersion = "(未知)"
$versionPath = Join-Path $GameRoot "version.txt"
if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
    $localGameVersion = (Get-Content -Raw -LiteralPath $versionPath).Trim()
}

Write-Stage "查询最新版本"
# Windows PowerShell 5.1 defaults to TLS 1.0 on older builds, which the
# object store refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Invoke-WebRequest's progress bar makes a 1 MB download take tens of seconds
# on 5.1; nobody needs it.
$ProgressPreference = "SilentlyContinue"
$bust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$remote = $null
foreach ($base in $UpdateBases) {
    try {
        $remote = Invoke-RestMethod -Uri "$base/manifest.json`?t=$bust" -UseBasicParsing -TimeoutSec 10
        if (Get-Prop $remote "package_version") { break }
        $remote = $null
    } catch {
        Write-Host "  连不上 $(([Uri]$base).Host)，换下一个..."
    }
}
if ($null -eq $remote) {
    throw "所有更新线路都连不上。$ManualHint"
}
$hint = [string](Get-Prop $remote "manual_hint")
if ($hint) { $ManualHint = $hint }
$latestVersion = [string](Get-Prop $remote "package_version")
$builtFor      = [string](Get-Prop $remote "built_for_game_version")
$notes         = [string](Get-Prop $remote "notes")
$file          = [string](Get-Prop $remote "win_file")
$url           = [string](Get-Prop $remote "win_url")
$wantHash      = [string](Get-Prop $remote "win_sha256")
if (-not $latestVersion -or -not ($file -or $url) -or -not $wantHash) {
    throw "更新服务器返回的信息不完整，本次不更新。"
}
# The zip is fetched from every mirror in turn, not just the one that served
# the manifest: its name carries the version, so a mirror either has this
# exact file or 404s, and the hash check below catches anything else.
$zipUrls = @()
if ($file) { $zipUrls += $UpdateBases | ForEach-Object { "$_/$file" } }
if ($url -and $zipUrls -notcontains $url) { $zipUrls += $url }

Write-Host "云端最新版本：$latestVersion（对应游戏版本 $builtFor）"
if ($latestVersion -eq $installedVersion) {
    Write-Host "`n已经是最新版本，无需更新。" -ForegroundColor Green
    Show-Popup "汉化：已是最新" "已安装的汉化（$installedVersion）就是最新版本。" 64
    exit 0
}

Write-Host ""
Write-Host "发现新版本：$installedVersion  ->  $latestVersion" -ForegroundColor Yellow
if ($notes) { Write-Host "更新内容：$notes" }
if ($builtFor -and $localGameVersion -ne $builtFor) {
    Write-Host "注意：这版汉化是按游戏版本 $builtFor 做的，你的游戏是 $localGameVersion。" -ForegroundColor Yellow
    Write-Host "      安装器会再做一次接口检查，不兼容时会自动停下，不会损坏游戏。" -ForegroundColor Yellow
}
if ($WaitForProcess -gt 0) {
    Write-Host "等待游戏退出..."
    while (Get-Process -Id $WaitForProcess -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 500 }
    # File handles can outlive the process object by a moment.
    Start-Sleep -Seconds 2
} elseif (-not $Yes) {
    Write-Host ""
    Write-Host "请先完全退出游戏。"
    $answer = Read-Host "现在更新吗？直接按回车开始，输入 n 取消"
    if ($answer -match '^[nN]') {
        Write-Host "已取消。"
        exit 0
    }
}

$workRoot = Join-Path ([IO.Path]::GetTempPath()) "travellingzh_update"
if ($Staged -and (Test-Path -LiteralPath $Staged -PathType Leaf)) {
    # Downloaded by the in-game plugin. Its hash is checked below against the
    # manifest exactly as a fresh download would be, so a stale or tampered
    # staged file is refused the same way.
    Write-Stage "使用游戏内已下载的更新包"
    $zipPath = $Staged
    $workRoot = Split-Path -Parent $Staged
} else {
    Write-Stage "下载更新包"
    if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    $zipPath = Join-Path $workRoot "update.zip"
    $ok = $false
    foreach ($u in $zipUrls) {
        try {
            Invoke-WebRequest -Uri $u -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
        } catch {
            Write-Host "  从 $(([Uri]$u).Host) 下载失败，换下一个..."
            continue
        }
        if ((Get-Sha256 $zipPath) -eq $wantHash.ToUpperInvariant()) { $ok = $true; break }
        Write-Host "  从 $(([Uri]$u).Host) 下载的文件校验不对，换下一个..."
    }
    if (-not $ok) {
        throw "更新包下载失败（所有线路都试过了）。$ManualHint"
    }
    $size = (Get-Item -LiteralPath $zipPath).Length
    Write-Host ("已下载 {0:N1} MB。" -f ($size / 1MB))
}

$gotHash = Get-Sha256 $zipPath
if ($gotHash -ne $wantHash.ToUpperInvariant()) {
    throw "更新包校验失败（文件可能下载不完整或被篡改），本次不安装。请重试。"
}
Write-Host "校验通过。"

Write-Stage "解压"
$extractRoot = Join-Path $workRoot "extract"
if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }
Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
$launcher = Get-ChildItem -LiteralPath $extractRoot -Recurse -Filter "launcher.ps1" |
    Where-Object { $_.Directory.Name -eq "installer_files" } | Select-Object -First 1
if ($null -eq $launcher) {
    throw "更新包里没有安装器，包可能已损坏。"
}

Write-Stage "安装"
# Same invocation the 【双击安装】 .cmd uses, plus the game directory so the
# installer does not have to rediscover it from a temp folder.
$psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
& $psExe -NoProfile -ExecutionPolicy Bypass -File $launcher.FullName -Action install -GameDir $GameRoot
$code = $LASTEXITCODE

if ($code -ne 0) {
    # The extracted package is left in place: install_result.log lives next
    # to it, and that is what the player is asked to send us.
    $log = Join-Path $launcher.Directory.Parent.FullName "install_result.log"
    throw "安装器报告失败（退出码 $code）。详细记录：$log"
}
try { Remove-Item -LiteralPath $workRoot -Recurse -Force } catch { }
Write-Host "`n更新完成：$latestVersion" -ForegroundColor Green
if ($WaitForProcess -gt 0) { Read-Host "按回车关闭" | Out-Null }
exit 0
