# Publishing a GitHub release

This script creates a GitHub release and uploads the Windows DLLs built by
`build-windows.ps1` as one zip file. Release notes are pulled automatically
from `CHANGELOG.md`. GitHub attaches the source code of the tag as `.zip` and
`.tar.gz` to every release on its own.

---

## Prerequisites

### GitHub CLI

The script uses the [GitHub CLI (`gh`)](https://cli.github.com/) to talk to the
GitHub API. Install it once:

```powershell
winget install --id GitHub.cli
```

After installation, authenticate with your GitHub account:

```powershell
gh auth login
```

Follow the prompts — select **GitHub.com**, **HTTPS**, and authenticate via
browser. The credentials are stored in your Windows credential manager; you
only have to do this once.

Verify it worked:

```powershell
gh auth status
```

---

## Full release workflow

These steps happen in order. The publish script only handles step 5.

### 1. Bump the version

Edit `php_sapnwrfc.h` and update `PHP_SAPNWRFC_VERSION`:

```c
#define PHP_SAPNWRFC_VERSION "2.2.0"
```

Also update the version in `docs/conf.py`.

### 2. Update CHANGELOG.md

Add a section for the new version above `[Unreleased]`:

```markdown
## [2.2.0] - 2026-06-14
### Added
- ...
### Fixed
- ...
```

The publish script reads this section verbatim as the GitHub release description.

### 3. Commit and tag

```powershell
git add php_sapnwrfc.h docs/conf.py CHANGELOG.md
git commit -m "release 2.2.0"
git tag v2.2.0
git push origin main v2.2.0
```

The tag must exist in the remote repository before you run the publish script.

### 4. Build the DLLs

```powershell
cd build
.\build-windows.ps1
```

This populates `build\output\` with one DLL per PHP variant, for example:

```
php_sapnwrfc-2.2.0+php.8.2.35-nts-vs16-x64.sdk.7540.719.35.dll
php_sapnwrfc-2.2.0+php.8.2.35-ts-vs16-x64.sdk.7540.719.35.dll
php_sapnwrfc-2.2.0+php.8.3.36-nts-vs16-x64.sdk.7540.719.35.dll
...
```

Only DLLs whose name starts with the current version (`php_sapnwrfc-2.2.0+`) are released.
Delete DLLs built with an older SAP SDK from `build\output\` first, otherwise they end up in
the zip as well.

### 5. Publish the release

```powershell
.\publish-github-release.ps1
```

The script:

1. Reads the version from `php_sapnwrfc.h` and derives the tag (`v2.2.0`)
2. Verifies that `gh` is authenticated and that the tag exists on `origin`
3. Takes the target repository from the `origin` remote, never from `upstream`
4. Collects all `php_sapnwrfc-{version}+*.dll` files from `build\output\` and skips DLLs
   built against a PHP pre-release such as `8.6.0RC4` (see `-IncludePrereleasePhp`)
5. Packs them into `php_sapnwrfc-{version}-windows-x64.zip` and writes a `.sha256` file for it
6. Extracts the matching section from `CHANGELOG.md` as the release description
7. Creates the release on GitHub and uploads the zip and its checksum

Release assets:

```
php_sapnwrfc-2.2.0-windows-x64.zip
php_sapnwrfc-2.2.0-windows-x64.zip.sha256
Source code (zip)                              ← added by GitHub
Source code (tar.gz)                           ← added by GitHub
```

Contents of the zip:

```
php_sapnwrfc-2.2.0-windows-x64├── php_sapnwrfc-2.2.0+php.8.2.35-nts-vs16-x64.sdk.7540.719.35.dll
├── php_sapnwrfc-2.2.0+php.8.2.35-ts-vs16-x64.sdk.7540.719.35.dll
├── ...                                        ← one DLL per PHP version and TS/NTS
├── CHANGELOG.md
├── LICENSE
└── SHA256SUMS.txt                             ← checksums of all DLLs
```

The SAP NW RFC SDK DLLs are not included; users obtain the SDK from SAP themselves (SAP account required).

---

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Tag` | Git tag to release, e.g. `v2.2.0` | Derived from `php_sapnwrfc.h` |
| `-OutputDir` | Directory containing the built DLLs | `.\output` |
| `-Draft` | Create as draft — lets you review before publishing | — |
| `-Prerelease` | Mark as pre-release on GitHub | — |
| `-IncludePrereleasePhp` | Also package DLLs built against PHP pre-releases (e.g. `8.6.0RC4`) | — |

---

## Recommended: publish as draft first

On your first release, use `-Draft` to check that everything looks correct on
GitHub before making it public:

```powershell
.\publish-github-release.ps1 -Draft
```

The script prints the URL to the draft. Open it, verify the description and
assets, then click **Publish release** in the browser.

---

## Troubleshooting

| Error | Cause / Fix |
|-------|-------------|
| `gh: command not found` | GitHub CLI not installed — run `winget install --id GitHub.cli` |
| `Not authenticated` | Run `gh auth login` |
| `Git tag 'vX.Y.Z' not found` | Tag not created yet — see step 3 above |
| `No DLLs found in .\output` | Run `build-windows.ps1` first |
| `gh release create failed` | Release for this tag may already exist — delete it on GitHub first, or choose a different tag |
| No release notes in description | Version heading in `CHANGELOG.md` does not match `PHP_SAPNWRFC_VERSION` exactly |
