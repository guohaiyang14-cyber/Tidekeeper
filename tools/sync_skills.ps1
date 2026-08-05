<#
.SYNOPSIS
  Sync tools/SKILL*.md to .trae/skills/<name>/SKILL.md (hardlinks)

.DESCRIPTION
  Scans tools/ for SKILL*.md files, reads frontmatter name field,
  creates hardlinks in .trae/skills/<name>/.
  To add a new skill: create tools/SKILL_<name>.md, run this script.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/sync_skills.ps1
#>

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $repoRoot "tools"
$skillsDir = Join-Path $repoRoot ".trae\skills"

Write-Output "=== Skill Sync ==="
Write-Output "Source:  $toolsDir"
Write-Output "Target:  $skillsDir"
Write-Output ""

if (-not (Test-Path $skillsDir)) {
    New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
}

# 1. Scan SKILL*.md files
$skillFiles = Get-ChildItem -Path $toolsDir -Filter "SKILL*.md" -File
if ($skillFiles.Count -eq 0) {
    Write-Output "WARN: No SKILL*.md found"
    exit 0
}

# 2. Parse frontmatter name field
$skillMap = @{}
foreach ($file in $skillFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match 'name:\s*"([^"]+)"') {
        $skillName = $matches[1]
        $skillMap[$skillName] = $file.FullName
        Write-Output "Found: $skillName -> $($file.Name)"
    } else {
        Write-Output "SKIP:  $($file.Name) (no frontmatter name)"
    }
}
Write-Output ""

# 3. Clean stale hardlinks (skill removed from tools/)
$existingDirs = Get-ChildItem -Path $skillsDir -Directory -ErrorAction SilentlyContinue
foreach ($dir in $existingDirs) {
    $skillName = $dir.Name
    if (-not $skillMap.ContainsKey($skillName)) {
        $staleFile = Join-Path $dir.FullName "SKILL.md"
        if (Test-Path $staleFile) { Remove-Item $staleFile -Force }
        Remove-Item $dir.FullName -Force
        Write-Output "Cleaned stale: $skillName"
    }
}

# 4. Create/update hardlinks
$synced = 0
$skipped = 0
foreach ($skillName in $skillMap.Keys) {
    $sourceFile = $skillMap[$skillName]
    $targetDir = Join-Path $skillsDir $skillName
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
            Write-Output "  OK   $skillName (already synced)"
        }
    }

    if ($needUpdate) {
        if (Test-Path $targetFile) { Remove-Item $targetFile -Force }
        New-Item -ItemType HardLink -Path $targetFile -Target $sourceFile | Out-Null
        $synced++
        Write-Output "  SYNC $skillName"
    }
}

Write-Output ""
Write-Output "=== Report ==="
Write-Output "Synced:  $synced"
Write-Output "Skipped: $skipped"
Write-Output "Total:   $($skillMap.Count) skill(s)"
