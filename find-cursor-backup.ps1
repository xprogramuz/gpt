#Requires -Version 5.1
<#
.SYNOPSIS
    Show where an old Cursor backup lives under Desktop\projects.
#>
[CmdletBinding()]
param(
    [string]$ProjectsPath = "C:\Users\Xp\Desktop\projects"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Add-UniquePath {
    param($List, [string]$Path)
    if (-not $Path) { return }
    foreach ($existing in $List) {
        if ([string]::Equals($existing, $Path, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    $List.Add($Path) | Out-Null
}

$roots = New-Object System.Collections.Generic.List[string]
Add-UniquePath $roots $ProjectsPath
Add-UniquePath $roots (Join-Path $env:USERPROFILE "Desktop\projects")
Add-UniquePath $roots (Join-Path $env:USERPROFILE "OneDrive\Desktop\projects")
if ($env:OneDrive) {
    Add-UniquePath $roots (Join-Path $env:OneDrive "Desktop\projects")
}

Write-Host ""
Write-Host "Eski Cursor qayerda?" -ForegroundColor White
Write-Host "====================" -ForegroundColor White
Write-Host "Cursor dasturi bu papkada emas. Bu yerda backup (sozlamalar, chatlar) bolishi mumkin."
Write-Host ""

$foundAnyRoot = $false
$hits = New-Object System.Collections.Generic.List[string]

foreach ($root in $roots) {
    Write-Host "Qidiriladi: $root"
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Host "  yoq" -ForegroundColor DarkGray
        continue
    }
    $foundAnyRoot = $true
    Write-Host "  bor. Ichidagi papkalar:" -ForegroundColor Green
    $children = Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Select-Object -First 50
    if (-not $children) {
        Write-Host "  (bosh)" -ForegroundColor Yellow
    } else {
        foreach ($child in $children) {
            Write-Host ("  {0,-12} {1}" -f $child.Mode, $child.Name)
        }
    }

    $markers = @(
        @{ Name = "settings.json"; Filter = "settings.json" },
        @{ Name = "state.vscdb"; Filter = "state.vscdb" },
        @{ Name = "keybindings.json"; Filter = "keybindings.json" }
    )
    foreach ($marker in $markers) {
        Get-ChildItem -LiteralPath $root -Recurse -Depth 8 -File -Filter $marker.Filter -Force -ErrorAction SilentlyContinue |
            Select-Object -First 15 |
            ForEach-Object { $hits.Add($_.FullName) | Out-Null }
    }
    Get-ChildItem -LiteralPath $root -Recurse -Depth 8 -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq ".cursor" -or $_.Name -eq "Cursor" } |
        Select-Object -First 20 |
        ForEach-Object { $hits.Add($_.FullName) | Out-Null }
}

Write-Host ""
if ($hits.Count -gt 0) {
    $unique = $hits | Select-Object -Unique
    Write-Host "Eski Cursor backup izlari:" -ForegroundColor Green
    foreach ($hit in $unique) {
        Write-Host "  $hit"
    }
    Write-Host ""
    Write-Host "Endi restore-cursor.bat ni ishga tushiring. U shu fayllarni yangi Cursorga qaytaradi."
} elseif (-not $foundAnyRoot) {
    Write-Host "Desktop\projects papkasi topilmadi." -ForegroundColor Red
    Write-Host "Explorer da tekshiring:"
    Write-Host "  C:\Users\Xp\Desktop\projects"
    Write-Host "  C:\Users\Xp\OneDrive\Desktop\projects"
} else {
    Write-Host "Bu papkalarda Cursor sozlamalari (settings.json, state.vscdb, .cursor) yoq." -ForegroundColor Yellow
    Write-Host "Demak bu yerda loyiha kodlari bolishi mumkin, lekin eski Cursor holati yoq."
    Write-Host ""
    Write-Host "Yana tekshiring:"
    Write-Host "  1) OneDrive / Google Drive / flashka"
    Write-Host "  2) Win+R -> %APPDATA%\Cursor  (hozirgi YANGI Cursor, odatda bosh)"
    Write-Host "  3) Cursor hisobi: Settings Sync yoqilgan bolsa, sozlamalar hisobdan qaytishi mumkin"
}

Write-Host ""
