---
description: Manage versioning, changelog, tagging, and APK releases for Hermes Android
---

# Release & Version Control Workflow

This workflow manages the full release cycle: version bump, changelog update, git tag, and APK deployment via CI.

## Project Context

- **Repo**: `danlil240/hermes-android`
- **Version source of truth**: `pubspec.yaml` line 4 — format `version: X.Y.Z+versionCode`
  - `X.Y.Z` = `versionName` (SemVer)
  - `+N` = Android `versionCode` (must always increase monotonically)
- **Gradle**: `android/app/build.gradle.kts` pulls `versionCode`/`versionName` from Flutter automatically — no manual gradle edits needed
- **CI**: `.github/workflows/build-apk.yml` triggers on `v*` tag push → builds signed split-per-ABI APKs → creates GitHub Release
- **Changelog**: `CHANGELOG.md` follows Keep a Changelog format under `## [X.Y.Z]` headings
- **Tag pattern**: `v1.0.0`, `v1.0.1`, etc. (no `v` prefix in pubspec, only in git tags)
- **Current version**: Check `pubspec.yaml` line 4 or run `git tag --sort=-v:refname | head -1`

## Steps

### 1. Determine Version Bump Type

Ask the user which type of release this is:

- **Patch** (e.g. `1.0.10` → `1.0.11`): Bug fixes, minor tweaks, no new features
- **Minor** (e.g. `1.0.10` → `1.1.0`): New features, backward-compatible changes
- **Major** (e.g. `1.0.10` → `2.0.0`): Breaking changes, major UI/architecture overhaul

Rules:
- Patch: increment Z by 1, increment versionCode by 1
- Minor: increment Y by 1, reset Z to 0, increment versionCode by 1
- Major: increment X by 1, reset Y and Z to 0, increment versionCode by 1
- versionCode (`+N`) must ALWAYS be greater than the previous release

### 2. Check Working Tree is Clean

// turbo
Verify there are no uncommitted changes before starting a release:

```bash
git status --porcelain
```

If output is not empty, warn the user and ask whether to stash or commit first. Do not proceed with a release on a dirty tree.

### 3. Read Current Version

Read `pubspec.yaml` line 4 to get the current version string. Parse it as:
- `versionName` = everything before `+`
- `versionCode` = everything after `+`

Also check the latest git tag to ensure consistency:

```bash
git tag --sort=-v:refname | head -1
```

If the latest tag's version doesn't match pubspec's versionName, warn the user — this means a previous release may have been incomplete.

### 4. Update `pubspec.yaml`

Edit line 4 of `pubspec.yaml` with the new version string.

Example: `1.0.10+110` → `1.0.11+111` (patch bump)

### 5. Update `CHANGELOG.md`

Add a new `## [X.Y.Z]` section at the top (after the header/intro text, before the previous version section).

Format:
```markdown
## [X.Y.Z]

### Added
- Description of new features

### Changed
- Description of changes

### Fixed
- Description of bug fixes
```

Only include sections that have entries. Ask the user for a summary of changes, or review recent git commits since the last tag:

```bash
git log $(git tag --sort=-v:refname | head -1)..HEAD --oneline --no-merges
```

### 6. Commit the Release

// turbo
```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "release: vX.Y.Z"
```

### 7. Tag the Release

// turbo
```bash
git tag vX.Y.Z
```

### 8. Push to Trigger CI

// turbo
```bash
git push origin HEAD --tags
```

This triggers `.github/workflows/build-apk.yml` which:
1. Sets up Flutter 3.44.0 + Java 17
2. Restores keystore from GitHub Secrets
3. Runs `flutter analyze` and `flutter test`
4. Builds `flutter build apk --release --split-per-abi`
5. Creates a GitHub Release with APK artifacts attached

### 9. Verify CI Build

Check the GitHub Actions status:

```bash
gh run list --workflow build-apk.yml --limit 1
```

If `gh` CLI is not available, the user can check at:
`https://github.com/danlil240/hermes-android/actions/workflows/build-apk.yml`

Wait for the build to complete. If it fails, diagnose the error and fix before re-tagging.

### 10. Verify GitHub Release

Confirm the release was created with APKs:

```bash
gh release view vX.Y.Z
```

The release should have 3 APK files attached (arm64-v8a, armeabi-v7a, x86_64).

### 11. Post-Release Checklist

- [ ] CI build passed (analyze + tests + APK build)
- [ ] GitHub Release created at `https://github.com/danlil240/hermes-android/releases/tag/vX.Y.Z`
- [ ] APKs attached to release (3 split-per-ABI files)
- [ ] Release notes generated or manually written
- [ ] `pubspec.yaml` version matches the git tag
- [ ] `CHANGELOG.md` updated with the new version section

## Hotfix Workflow

For urgent bug fixes off the latest release:

1. Create a hotfix branch from the latest tag:
   ```bash
   git checkout -b hotfix/vX.Y.Z+1 vX.Y.Z
   ```
2. Fix the bug, commit changes
3. Follow steps 4-8 above (patch bump)
4. Merge hotfix branch back to main:
   ```bash
   git checkout main
   git merge hotfix/vX.Y.Z+1
   git push origin main
   ```
5. Delete the hotfix branch:
   ```bash
   git branch -d hotfix/vX.Y.Z+1
   ```

## Pre-Release / Beta Workflow

For testing before a full release:

1. Bump version as usual but add a pre-release suffix in the tag:
   ```
   v1.1.0-beta.1
   ```
2. Note: `pubspec.yaml` version should NOT have the beta suffix — keep it as `1.1.0+120`
3. Tag with beta suffix and push:
   ```bash
   git tag v1.1.0-beta.1
   git push origin v1.1.0-beta.1
   ```
4. The CI workflow triggers on `v*` tags, so beta tags will also build
5. Mark the GitHub Release as a pre-release:
   ```bash
   gh release edit v1.1.0-beta.1 --prerelease
   ```
6. For the final release, tag without suffix: `v1.1.0`

## Rollback

If a release has a critical issue:

1. **Do NOT delete the tag** — it's published and users may have it
2. Create a new patch release with the fix (follow normal workflow)
3. If absolutely necessary, mark the bad release as a draft on GitHub:
   ```bash
   gh release edit vX.Y.Z --draft
   ```

## Keystore Notes

- The release keystore is stored as `KEYSTORE_BASE64` in GitHub Secrets
- `key.properties` and `.keystore` files are gitignored — never commit them
- **Back up the keystore file offline** — if lost, you cannot publish updates with the same signing identity
- Debug builds use the debug keystore automatically; release builds use the configured release keystore

## Version Consistency Check

Before tagging, always verify that the pubspec version matches the intended tag:

```bash
PUBSPEC_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d '+' -f 1)
TAG_VERSION="X.Y.Z"  # the version you're about to tag
if [ "$PUBSPEC_VERSION" != "$TAG_VERSION" ]; then
  echo "MISMATCH: pubspec=$PUBSPEC_VERSION tag=$TAG_VERSION"
  exit 1
fi
```
