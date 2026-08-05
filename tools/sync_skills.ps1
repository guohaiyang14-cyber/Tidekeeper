<#
.SYNOPSIS
  Sync tools/SKILL*.md to Trae + Cursor skill directories (hardlinks)

.DESCRIPTION
  Scans tools/ for SKILL*.md files, reads frontmatter name field,
  creates hardlinks in:
    - .trae/skills/<name>/SKILL.md
    - .cursor/skills/<name>/SKILL.md
  To add a new skill: create tools/SKILL_<name>.md, run this script.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/sync_skills.ps1
#>

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $repoRoot "tools"
$targets = @(
    (Join-Path $repoRoot ".trae\skills"),
    (Join-Path $repoRoot ".cursor\skills")
)

Write-Output "=== Skill Sync ==="
Write-Output "Source:  $toolsDir"
Write-Output ""

# 1. Scan SKILL*.md files
$skillFiles = Get-ChildItem -Path $toolsDir -Filter "SKILL*.md" -File
if ($skillFiles.Count -eq 0) {
    Write-Output "WARN: No SKILL*.md found"
    exit 0
}

# 2. Parse frontmatter name field (quoted or bare)
$skillMap = @{}
foreach ($file in $skillFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match 'name:\s*"([^"]+)"') {
        $skillName = $matches[1]
    } elseif ($content -match 'name:\s*([a-z0-9-]+)') {
        $skillName = $matches[1]
    } else {
        Write-Output "SKIP:  $($file.Name) (no frontmatter name)"
        continue
    }
    $skillMap[$skillName] = $file.FullName
    Write-Output "Found: $skillName -> $($file.Name)"
}
Write-Output ""

function Sync-SkillDir {
    param(
        [string]$SkillsDir,
        [hashtable]$Map
    )

    if (-not (Test-Path $SkillsDir)) {
        New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null
    }

    Write-Output "Target: $SkillsDir"

    # Clean stale
    $existingDirs = Get-ChildItem -Path $SkillsDir -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $existingDirs) {
        $skillName = $dir.Name
        if (-not $Map.ContainsKey($skillName)) {
            $staleFile = Join-Path $dir.FullName "SKILL.md"
            if (Test-Path $staleFile) { Remove-Item $staleFile -Force }
            Remove-Item $dir.FullName -Force -Recurse
            Write-Output "  Cleaned stale: $skillName"
        }
    }

    $synced = 0
    $skipped = 0
    foreach ($skillName in $Map.Keys) {
        $sourceFile = $Map[$skillName]
        $targetDir = Join-Path $SkillsDir $skillName
        $targetFile = Join-Path $targetDir "SKILL.md"

        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }

        $needUpdate = $true
        if (Test-Path $targetFile) {
            $sourceHash = (Get-FileHash $sourceFile).Hash
            $targetHash = (Get-FileHash $targetFile).Hash
            if ($sourceHash -eq $targetHash) {
                $needUpdate = $false
                $skipped++
                Write-Output "  OK   $skillName"
            }
        }

        if ($needUpdate) {
            if (Test-Path $targetFile) { Remove-Item $targetFile -Force }
            New-Item -ItemType HardLink -Path $targetFile -Target $sourceFile | Out-Null
            $synced++
            Write-Output "  SYNC $skillName"
        }
    }

    Write-Output "  -> synced=$synced skipped=$skipped"
    Write-Output ""
}

foreach ($dir in $targets) {
    Sync-SkillDir -SkillsDir $dir -Map $skillMap
}

Write-Output "=== Report ==="
Write-Output "Total skills: $($skillMap.Count)"
Write-Output ($skillMap.Keys | Sort-Object | ForEach-Object { "  - $_" })
