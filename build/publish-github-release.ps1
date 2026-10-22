#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a GitHub release for php-sapnwrfc and uploads the built Windows DLLs.

.DESCRIPTION
    Reads the extension version from php_sapnwrfc.h, collects all DLLs from the
    output directory, extracts release notes from CHANGELOG.md, and creates a
    GitHub release via the gh CLI.

    Run build-windows.ps1 first to populate the output directory.

.PARAMETER Tag
    The git tag to release (e.g. "v2.1.0"). Defaults to "v{version}" read from
    php_sapnwrfc.h. The tag must already exist in the repository.

.PARAMETER OutputDir
    Directory containing the built DLLs. Default: ".\output".

.PARAMETER Draft
    Create the release as a draft so you can review it before publishing.

.PARAMETER Prerelease
    Mark the release as a pre-release on GitHub.

.PARAMETER IncludePrereleasePhp
    Also package DLLs built against PHP pre-releases (e.g. 8.6.0RC4). By default
    they are left out, because a DLL built against a release candidate is not
    guaranteed to load in the final PHP release.

.EXAMPLE
    .\publish-github-release.ps1
    Create a release for the version in php_sapnwrfc.h, publish immediately.

.EXAMPLE
    .\publish-github-release.ps1 -Draft
    Create a draft release for review before publishing.

.EXAMPLE
    .\publish-github-release.ps1 -Tag v2.1.0 -OutputDir D:\build\output -Draft
    Create a draft release for a specific tag using DLLs from a custom directory.
#>
[CmdletBinding()]
param(
    [string]$Tag       = "",
    [string]$OutputDir = "",
    [switch]$Draft,
    [switch]$Prerelease,
    [switch]$IncludePrereleasePhp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail([string]$msg) { Write-Error $msg -ErrorAction Continue; exit 1 }

$RepoRoot  = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $OutputDir) { $OutputDir = Join-Path $PSScriptRoot "output" }

# ---------------------------------------------------------------------------
# Read extension version
# ---------------------------------------------------------------------------
Step "Reading extension version"

$versionHeader = Join-Path $RepoRoot "php_sapnwrfc.h"
$extVersion = $null
if (Test-Path $versionHeader) {
    $headerContent = Get-Content $versionHeader -Raw
    if ($headerContent -match '#define\s+PHP_SAPNWRFC_VERSION\s+"([^"]+)"') {
        $extVersion = $Matches[1]
    }
}
if (-not $extVersion) { Fail "Could not read PHP_SAPNWRFC_VERSION from $versionHeader" }
Write-Host "  Extension version : $extVersion"

if (-not $Tag) { $Tag = "v$extVersion" }
Write-Host "  Git tag           : $Tag"

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
Step "Checking prerequisites"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail ("GitHub CLI (gh) not found.`n" +
          "  Install from https://cli.github.com/ then run: gh auth login")
}

gh auth status 2>&1 | Out-Null
$ghAuthExit = $LASTEXITCODE
if ($ghAuthExit -ne 0) {
    Fail "Not authenticated. Run: gh auth login"
}
Write-Host "  gh CLI authenticated"

# Always release to origin; with several remotes (e.g. upstream) gh would
# otherwise pick or prompt for a repository on its own.
$originUrl = git -C $RepoRoot remote get-url origin 2>$null
if ($originUrl -notmatch 'github\.com[:/]([^/]+/[^/]+?)(\.git)?$') {
    Fail "Remote 'origin' ($originUrl) is not a GitHub repository"
}
$repo = $Matches[1]
Write-Host "  Target repository : $repo"

$remoteTag = git -C $RepoRoot ls-remote --tags origin "refs/tags/$Tag" 2>$null
$gitLsRemoteExit = $LASTEXITCODE
if ($gitLsRemoteExit -ne 0) {
    Fail "Could not query remote tags (git exited $gitLsRemoteExit). Ensure 'origin' is configured and the remote is accessible."
}
if (-not $remoteTag) {
    Fail ("Git tag '$Tag' not found on remote.`n" +
          "  Create and push it first:`n" +
          "    git tag $Tag`n" +
          "    git push origin $Tag")
}
Write-Host "  Git tag '$Tag' found on remote"

# ---------------------------------------------------------------------------
# Collect DLLs
# ---------------------------------------------------------------------------
Step "Collecting DLLs from $OutputDir"

$dlls = @(Get-ChildItem -Path $OutputDir -Filter "php_sapnwrfc-$extVersion+*.dll" -ErrorAction SilentlyContinue)
if ($dlls.Count -eq 0) {
    Fail ("No DLLs found in $OutputDir.`n" +
          "  Run build-windows.ps1 first.")
}
if (-not $IncludePrereleasePhp) {
    $skipped = @($dlls | Where-Object { $_.Name -match '\+php\.\d+\.\d+\.\d+(alpha|beta|RC)\d+-' })
    foreach ($dll in $skipped) { Write-Host "  skipped (PHP pre-release): $($dll.Name)" }
    $dlls = @($dlls | Where-Object { $skipped -notcontains $_ })
    if ($dlls.Count -eq 0) { Fail "Only DLLs for PHP pre-releases found - use -IncludePrereleasePhp" }
}
foreach ($dll in $dlls) { Write-Host "  $($dll.Name)" }

# ---------------------------------------------------------------------------
# Package DLLs into a zip with checksums
# ---------------------------------------------------------------------------
Step "Packaging DLLs"

$stageDir = Join-Path $env:TEMP "sapnwrfc_release_$([System.IO.Path]::GetRandomFileName().Replace('.',''))"
$pkgName  = "php_sapnwrfc-$extVersion-windows-x64"
$pkgDir   = Join-Path $stageDir $pkgName
New-Item -ItemType Directory -Force $pkgDir | Out-Null

foreach ($dll in $dlls) { Copy-Item $dll.FullName $pkgDir }
foreach ($doc in @("LICENSE", "CHANGELOG.md")) {
    $docPath = Join-Path $RepoRoot $doc
    if (Test-Path $docPath) { Copy-Item $docPath $pkgDir }
}

# sha256sum-compatible lines: "<hash> *<file>", LF line endings so that
# "sha256sum -c" also works on Linux
function Get-Sha256Line([string]$path) {
    "$((Get-FileHash $path -Algorithm SHA256).Hash.ToLower()) *$(Split-Path $path -Leaf)`n"
}
$dllSums = ($dlls | Sort-Object Name | ForEach-Object { Get-Sha256Line $_.FullName }) -join ""
[System.IO.File]::WriteAllText((Join-Path $pkgDir "SHA256SUMS.txt"), $dllSums)

$zipPath = Join-Path $stageDir "$pkgName.zip"
Compress-Archive -Path $pkgDir -DestinationPath $zipPath
$zipSumPath = "$zipPath.sha256"
[System.IO.File]::WriteAllText($zipSumPath, (Get-Sha256Line $zipPath))
Write-Host "  $pkgName.zip ($($dlls.Count) DLLs, LICENSE, CHANGELOG.md, SHA256SUMS.txt)"

# ---------------------------------------------------------------------------
# Extract release notes from CHANGELOG.md
# ---------------------------------------------------------------------------
Step "Extracting release notes from CHANGELOG.md"

$notesFile = $null
$changelog = Join-Path $RepoRoot "CHANGELOG.md"
if (Test-Path $changelog) {
    $content = Get-Content $changelog -Raw
    $escaped = [regex]::Escape($extVersion)
    if ($content -match "(?ms)^## \[$escaped\][^\n]*\n(.*?)(?=^## |\z)") {
        $notes = $Matches[1].Trim()
        if ($notes) {
            $notesFile = Join-Path $env:TEMP "sapnwrfc_notes_$([System.IO.Path]::GetRandomFileName()).md"
            Set-Content -Path $notesFile -Value $notes -Encoding UTF8
            Write-Host "  Found ($($notes.Length) chars)"
        }
    }
}
if (-not $notesFile) {
    Write-Warning "No release notes found for $extVersion in CHANGELOG.md — release will have no description"
}

# ---------------------------------------------------------------------------
# Create GitHub release
# ---------------------------------------------------------------------------
Step "Creating GitHub release $Tag"

$modeLabel = if ($Draft) { "draft " } else { "" }
Write-Host "  Uploading $pkgName.zip as ${modeLabel}release..."

$ghArgs = @("release", "create", $Tag, $zipPath, $zipSumPath, "--repo", $repo)
$ghArgs += "--title", "v$extVersion"
if ($notesFile) {
    $ghArgs += "--notes-file", $notesFile
} else {
    $ghArgs += "--notes", ""
}
if ($Draft)      { $ghArgs += "--draft" }
if ($Prerelease) { $ghArgs += "--prerelease" }

try {
    & gh @ghArgs
    if ($LASTEXITCODE -ne 0) { Fail "gh release create failed (exit $LASTEXITCODE)" }
} finally {
    if ($notesFile -and (Test-Path $notesFile)) {
        Remove-Item $notesFile -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $stageDir -Recurse -Force -ErrorAction SilentlyContinue
}

$releaseUrl = gh release view $Tag --repo $repo --json url --jq .url 2>$null

Step "Done"
if ($Draft) {
    Write-Host "  Draft release created — review and publish at:" -ForegroundColor Yellow
} else {
    Write-Host "  Release published:" -ForegroundColor Green
}
if ($releaseUrl) { Write-Host "  $releaseUrl" -ForegroundColor White }
