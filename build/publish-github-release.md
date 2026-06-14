# Publishing a GitHub release

This script creates a GitHub release and uploads the Windows DLLs built by
`build-windows.ps1` as release assets. Release notes are pulled automatically
from `CHANGELOG.md`.

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
git push origin main --tags
```

The tag must exist in the remote repository before you run the publish script.

### 4. Build the DLLs

```powershell
cd build
.\build-windows.ps1
```

This populates `build\output\` with one DLL per PHP variant, for example:

```
php_sapnwrfc-2.2.0+php.8.2.31-nts-vs16-x64.sdk.7500.0.13.dll
php_sapnwrfc-2.2.0+php.8.2.31-ts-vs16-x64.sdk.7500.0.13.dll
php_sapnwrfc-2.2.0+php.8.3.31-nts-vs16-x64.sdk.7500.0.13.dll
...
```

### 5. Publish the release

```powershell
.\publish-github-release.ps1
```

The script:

1. Reads the version from `php_sapnwrfc.h` and derives the tag (`v2.2.0`)
2. Verifies the tag exists in git and that `gh` is authenticated
3. Collects all `php_sapnwrfc-*.dll` files from `build\output\`
4. Extracts the matching section from `CHANGELOG.md` as the release description
5. Creates the release on GitHub and uploads all DLLs as assets

---

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Tag` | Git tag to release, e.g. `v2.2.0` | Derived from `php_sapnwrfc.h` |
| `-OutputDir` | Directory containing the built DLLs | `.\output` |
| `-Draft` | Create as draft — lets you review before publishing | — |
| `-Prerelease` | Mark as pre-release on GitHub | — |

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
