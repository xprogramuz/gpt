#Requires -Version 5.1
<#
.SYNOPSIS
    Restore Cursor IDE to the previous state from a local backup folder.

.DESCRIPTION
    Copies Cursor settings, keybindings, chat history, extensions, MCP config,
    and agent transcripts from the backup into the live Windows Cursor folders.

    Default backup path:
      C:\Users\Xp\Desktop\projects\cursor-backup

    Cursor must not be running while files are copied. This script closes it.

.EXAMPLE
    .\restore-cursor.ps1
    .\restore-cursor.ps1 -Inventory
    .\restore-cursor.ps1 -WhatIf
    .\restore-cursor.ps1 -BackupPath "D:\old\cursor-backup"
#>
[CmdletBinding()]
param(
    [string]$BackupPath = "C:\Users\Xp\Desktop\projects\cursor-backup",
    [switch]$WhatIf,
    [switch]$Inventory,
    [switch]$KeepCursorRunning
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$LiveRoaming = Join-Path $env:APPDATA "Cursor"
$LiveDotCursor = Join-Path $env:USERPROFILE ".cursor"
$SafetyRoot = Join-Path ([Environment]::GetFolderPath("Desktop")) "projects\cursor-pre-restore"

$RoamingSkipNames = @(
    "Cache",
    "CachedData",
    "CachedExtensions",
    "Code Cache",
    "Crashpad",
    "DawnCache",
    "DawnGraphiteCache",
    "DawnWebGPUCache",
    "GPUCache",
    "logs",
    "Service Worker",
    "ShaderCache",
    "VideoDecodeStats"
)

function Write-Info($Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Ok($Message) { Write-Host $Message -ForegroundColor Green }
function Write-WarnMsg($Message) { Write-Host $Message -ForegroundColor Yellow }
function Write-ErrMsg($Message) { Write-Host $Message -ForegroundColor Red }

function Test-LooksLikeRoamingCursor {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $user = Join-Path $Path "User"
    $settings = Join-Path $user "settings.json"
    $globalStorage = Join-Path $user "globalStorage"
    $keybindings = Join-Path $user "keybindings.json"
    $storage = Join-Path $Path "storage.json"
    return (Test-Path -LiteralPath $settings) -or
        (Test-Path -LiteralPath $globalStorage) -or
        (Test-Path -LiteralPath $keybindings) -or
        (Test-Path -LiteralPath $storage)
}

function Test-LooksLikeDotCursor {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $markers = @(
        (Join-Path $Path "argv.json"),
        (Join-Path $Path "mcp.json"),
        (Join-Path $Path "ide_state.json"),
        (Join-Path $Path "extensions"),
        (Join-Path $Path "projects"),
        (Join-Path $Path "skills-cursor"),
        (Join-Path $Path "ai-tracking")
    )
    foreach ($marker in $markers) {
        if (Test-Path -LiteralPath $marker) { return $true }
    }
    return $false
}

function Find-DirectoryByName {
    param(
        [string]$Root,
        [string]$Name,
        [int]$Depth = 6
    )
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    $matches = New-Object System.Collections.Generic.List[string]
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue(@{ Path = $Root; Depth = 0 })
    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()
        if ($item.Depth -gt $Depth) { continue }
        try {
            $dirs = Get-ChildItem -LiteralPath $item.Path -Directory -Force -ErrorAction SilentlyContinue
        } catch {
            continue
        }
        foreach ($dir in $dirs) {
            if ($dir.Name -ieq $Name) {
                $matches.Add($dir.FullName) | Out-Null
            }
            if ($item.Depth -lt $Depth) {
                $queue.Enqueue(@{ Path = $dir.FullName; Depth = ($item.Depth + 1) })
            }
        }
    }
    return $matches
}

function Resolve-BackupLayout {
    param([string]$Root)

    $layout = [ordered]@{
        BackupRoot     = $Root
        RoamingCursor  = $null
        DotCursor      = $null
        LooseUser      = $null
        LooseSettings  = $null
        LooseKeybinds  = $null
        LooseSnippets  = $null
        LooseExtensionsTxt = $null
        Notes          = New-Object System.Collections.Generic.List[string]
    }

    $roamingCandidates = @(
        (Join-Path $Root "Cursor"),
        (Join-Path $Root "AppData\Roaming\Cursor"),
        (Join-Path $Root "Roaming\Cursor"),
        (Join-Path $Root "AppData\Cursor"),
        (Join-Path $Root "Users\Xp\AppData\Roaming\Cursor"),
        (Join-Path $Root "Xp\AppData\Roaming\Cursor"),
        $Root
    )

    foreach ($candidate in $roamingCandidates) {
        if (Test-LooksLikeRoamingCursor $candidate) {
            $layout.RoamingCursor = $candidate
            break
        }
    }

    if (-not $layout.RoamingCursor) {
        foreach ($userDir in (Find-DirectoryByName -Root $Root -Name "User" -Depth 6)) {
            $parent = Split-Path -LiteralPath $userDir -Parent
            if (Test-LooksLikeRoamingCursor $parent) {
                $layout.RoamingCursor = $parent
                $layout.Notes.Add("Roaming Cursor papkasi User ichidan topildi: $parent") | Out-Null
                break
            }
            $settings = Join-Path $userDir "settings.json"
            $globalStorage = Join-Path $userDir "globalStorage"
            if ((Test-Path -LiteralPath $settings) -or (Test-Path -LiteralPath $globalStorage)) {
                $layout.LooseUser = $userDir
            }
        }
    }

    $dotCandidates = @(
        (Join-Path $Root ".cursor"),
        (Join-Path $Root "dot-cursor"),
        (Join-Path $Root "dotcursor"),
        (Join-Path $Root "cursor-home"),
        (Join-Path $Root "Users\Xp\.cursor"),
        (Join-Path $Root "Xp\.cursor")
    )

    foreach ($candidate in $dotCandidates) {
        if (Test-LooksLikeDotCursor $candidate) {
            $layout.DotCursor = $candidate
            break
        }
    }

    if (-not $layout.DotCursor) {
        foreach ($dir in (Find-DirectoryByName -Root $Root -Name ".cursor" -Depth 6)) {
            if (Test-LooksLikeDotCursor $dir) {
                $layout.DotCursor = $dir
                $layout.Notes.Add(".cursor papkasi ichkaridan topildi: $dir") | Out-Null
                break
            }
        }
    }

    $looseSettings = Join-Path $Root "settings.json"
    $looseKeybinds = Join-Path $Root "keybindings.json"
    $looseSnippets = Join-Path $Root "snippets"
    $looseExt = Join-Path $Root "extensions.txt"
    $looseExtJson = Join-Path $Root "extensions.json"

    if (Test-Path -LiteralPath $looseSettings) { $layout.LooseSettings = $looseSettings }
    if (Test-Path -LiteralPath $looseKeybinds) { $layout.LooseKeybinds = $looseKeybinds }
    if (Test-Path -LiteralPath $looseSnippets) { $layout.LooseSnippets = $looseSnippets }
    if (Test-Path -LiteralPath $looseExt) { $layout.LooseExtensionsTxt = $looseExt }
    elseif (Test-Path -LiteralPath $looseExtJson) { $layout.LooseExtensionsTxt = $looseExtJson }

    return $layout
}

function Get-LayoutSummary {
    param($Layout)
    $found = @()
    if ($Layout.RoamingCursor) { $found += "Cursor sozlamalari/chatlar: $($Layout.RoamingCursor)" }
    if ($Layout.DotCursor) { $found += "Kengaytmalar/MCP/agent: $($Layout.DotCursor)" }
    if ($Layout.LooseUser) { $found += "User papkasi: $($Layout.LooseUser)" }
    if ($Layout.LooseSettings) { $found += "settings.json: $($Layout.LooseSettings)" }
    if ($Layout.LooseKeybinds) { $found += "keybindings.json: $($Layout.LooseKeybinds)" }
    if ($Layout.LooseSnippets) { $found += "snippets: $($Layout.LooseSnippets)" }
    if ($Layout.LooseExtensionsTxt) { $found += "extensions royxati: $($Layout.LooseExtensionsTxt)" }
    foreach ($note in $Layout.Notes) { $found += $note }
    return $found
}

function Test-HasRestorableData {
    param($Layout)
    return [bool](
        $Layout.RoamingCursor -or
        $Layout.DotCursor -or
        $Layout.LooseUser -or
        $Layout.LooseSettings -or
        $Layout.LooseKeybinds -or
        $Layout.LooseSnippets -or
        $Layout.LooseExtensionsTxt
    )
}

function Stop-CursorIfRunning {
    if ($KeepCursorRunning) {
        Write-WarnMsg "Cursor yopilmadi (-KeepCursorRunning). Nusxa xato bolishi mumkin."
        return
    }
    $names = @("Cursor", "Cursor Helper", "Cursor Helper (GPU)", "Cursor Helper (Renderer)", "Cursor Helper (Plugin)")
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $names -contains $_.ProcessName -or $_.ProcessName -like "Cursor*"
    }
    if (-not $procs) {
        Write-Ok "Cursor yopiq. Davom etamiz."
        return
    }
    Write-Info "Cursor yopilmoqda..."
    foreach ($proc in $procs) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
    }
    Start-Sleep -Seconds 2
    $left = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Cursor*" }
    if ($left) {
        throw "Cursor hali ham ishlayapti. Task Manager dan yoping va skriptni qayta ishga tushiring."
    }
    Write-Ok "Cursor yopildi."
}

function Copy-Tree {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$SkipNames = @()
    )
    if ($WhatIf) {
        Write-Host "  WHATIF: $Source -> $Destination"
        return
    }
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $robocopy = Join-Path $env:SystemRoot "System32\robocopy.exe"
    if (Test-Path -LiteralPath $robocopy) {
        $xd = @()
        if ($SkipNames.Count -gt 0) {
            $xd = @("/XD") + $SkipNames
        }
        $args = @($Source, $Destination, "/E", "/COPY:DAT", "/R:1", "/W:1", "/NFL", "/NDL", "/NJH", "/NJS", "/NP") + $xd
        & $robocopy @args | Out-Null
        # robocopy exit codes 0-7 are success
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy muvaffaqiyatsiz: $Source -> $Destination (kod $LASTEXITCODE)"
        }
        return
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Copy-FileTo {
    param(
        [string]$Source,
        [string]$Destination
    )
    if ($WhatIf) {
        Write-Host "  WHATIF: $Source -> $Destination"
        return
    }
    $dir = Split-Path -LiteralPath $Destination -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Backup-LiveCursor {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $dest = Join-Path $SafetyRoot $stamp
    if ($WhatIf) {
        Write-Host "WHATIF: joriy Cursor holati $dest ga saqlanadi"
        return $dest
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    if (Test-Path -LiteralPath $LiveRoaming) {
        Copy-Tree -Source $LiveRoaming -Destination (Join-Path $dest "Cursor") -SkipNames $RoamingSkipNames
    }
    if (Test-Path -LiteralPath $LiveDotCursor) {
        Copy-Tree -Source $LiveDotCursor -Destination (Join-Path $dest "dot-cursor")
    }
    Write-Ok "Joriy holat saqlandi: $dest"
    return $dest
}

function Restore-ExtensionsList {
    param([string]$ListPath)
    if (-not (Get-Command cursor -ErrorAction SilentlyContinue)) {
        Write-WarnMsg "cursor CLI topilmadi. Kengaytmalar royxati nusxalandi, lekin avtomatik ornata olmadim."
        return
    }
    $lines = Get-Content -LiteralPath $ListPath | Where-Object { $_ -and $_.Trim() -and ($_ -notmatch '^\s*#') }
    foreach ($id in $lines) {
        $extId = $id.Trim()
        if ($extId -match '"') { continue }
        if ($WhatIf) {
            Write-Host "  WHATIF: cursor --install-extension $extId"
            continue
        }
        Write-Info "Kengaytma: $extId"
        & cursor --install-extension $extId | Out-Null
    }
}

function Show-Inventory {
    param($Layout, [string]$Root)
    Write-Host ""
    Write-Host "=== Backup tarkibi ===" -ForegroundColor White
    Write-Host "Manba: $Root"
    Write-Host ""
    $summary = Get-LayoutSummary $Layout
    if ($summary.Count -eq 0) {
        Write-ErrMsg "Cursor sozlamalari topilmadi."
        Write-Host "Papkada nima bor:"
        Get-ChildItem -LiteralPath $Root -Force | Select-Object -First 30 | ForEach-Object {
            Write-Host ("  {0,-12} {1}" -f $_.Mode, $_.Name)
        }
        return
    }
    foreach ($line in $summary) {
        Write-Ok ("- " + $line)
    }

    $stateDb = $null
    if ($Layout.RoamingCursor) {
        $stateDb = Join-Path $Layout.RoamingCursor "User\globalStorage\state.vscdb"
    } elseif ($Layout.LooseUser) {
        $stateDb = Join-Path $Layout.LooseUser "globalStorage\state.vscdb"
    }
    if ($stateDb -and (Test-Path -LiteralPath $stateDb)) {
        $item = Get-Item -LiteralPath $stateDb
        Write-Ok ("- Chat bazasi: {0} ({1:N1} MB, {2})" -f $item.FullName, ($item.Length / 1MB), $item.LastWriteTime)
    } else {
        Write-WarnMsg "- Chat bazasi (state.vscdb) topilmadi. Suhbatlar tiklanmasligi mumkin."
    }
}

# --- main ---

Write-Host ""
Write-Host "Cursor ni eski holatiga qaytarish" -ForegroundColor White
Write-Host "=================================" -ForegroundColor White

if (-not (Test-Path -LiteralPath $BackupPath)) {
    Write-ErrMsg "Backup papkasi yoq: $BackupPath"
    Write-Host ""
    Write-Host "Tekshiring:"
    Write-Host "  1) Papka haqiqatan ham bor-mi (Explorer da oching)"
    Write-Host "  2) Boshqa diskda bolsa: .\restore-cursor.ps1 -BackupPath `"D:\path\cursor-backup`""
    exit 1
}

$layout = Resolve-BackupLayout -Root $BackupPath
Show-Inventory -Layout $layout -Root $BackupPath

if ($Inventory) {
    exit 0
}

if (-not (Test-HasRestorableData $layout)) {
    Write-Host ""
    Write-ErrMsg "Bu papkada tiklash uchun Cursor malumotlari yoq."
    Write-Host "Kutilgan narsalar: AppData\Roaming\Cursor, .cursor, settings.json, state.vscdb"
    exit 1
}

if ($WhatIf) {
    Write-WarnMsg "`nDry-run: hech narsa ozgartirilmaydi."
}

Write-Host ""
Write-Info "Qayerga tiklanadi:"
Write-Host "  $LiveRoaming"
Write-Host "  $LiveDotCursor"

Stop-CursorIfRunning
$safety = Backup-LiveCursor

Write-Host ""
Write-Info "Backupdan tiklash..."

if ($layout.RoamingCursor) {
    Write-Info "Sozlamalar, chatlar, workspace holati..."
    Copy-Tree -Source $layout.RoamingCursor -Destination $LiveRoaming -SkipNames $RoamingSkipNames
}

if ($layout.LooseUser -and -not $layout.RoamingCursor) {
    Write-Info "User papkasi..."
    Copy-Tree -Source $layout.LooseUser -Destination (Join-Path $LiveRoaming "User")
}

if ($layout.DotCursor) {
    Write-Info "Kengaytmalar, MCP, agent tarixi..."
    Copy-Tree -Source $layout.DotCursor -Destination $LiveDotCursor
}

if ($layout.LooseSettings) {
    Copy-FileTo -Source $layout.LooseSettings -Destination (Join-Path $LiveRoaming "User\settings.json")
}
if ($layout.LooseKeybinds) {
    Copy-FileTo -Source $layout.LooseKeybinds -Destination (Join-Path $LiveRoaming "User\keybindings.json")
}
if ($layout.LooseSnippets) {
    Copy-Tree -Source $layout.LooseSnippets -Destination (Join-Path $LiveRoaming "User\snippets")
}
if ($layout.LooseExtensionsTxt) {
    Restore-ExtensionsList -ListPath $layout.LooseExtensionsTxt
}

Write-Host ""
Write-Ok "Tiklash tugadi."
Write-Host "Xavfsizlik nusxasi: $safety"
Write-Host ""
Write-Host "Keyingi qadamlar:"
Write-Host "  1. Cursor ni oching va bir xil hisob bilan kiring."
Write-Host "  2. Loyihalarni ESKI papka yolidan oching. Chatlar yo'lga bog'liq."
Write-Host "     Masalan, avval C:\Users\Xp\Desktop\projects\... bolsa, yana shu yolni oching."
Write-Host "  3. Settings Sync conflict chiqsa, backupdagi sozlamalarni saqlang (Keep Local / merge)."
Write-Host ""
