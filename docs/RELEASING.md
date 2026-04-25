# Releasing Gitbar

End-to-end steps for cutting a new release. Mirrors how v0.2.0 went out.

## TL;DR

```
flo release            # interactive: prompts bump type, opens $EDITOR for notes
```

That single command runs every step in this doc end-to-end. The rest of the doc
explains what it does, and serves as the manual fallback if the script breaks.

## Versioning

Pre-1.0, we follow a relaxed semver:

- **Patch (`0.x.Y`)** — fixes, polish, internal changes only.
- **Minor (`0.X.0`)** — any new user-facing capability (new section type, new filter, new tab, default behavior change).
- **Major (`X.0.0`)** — reserved for 1.0 and beyond.

When in doubt, prefer minor over patch. A version is cheap; mis-signaling a release isn't.

## Manual fallback

The steps below are what `scripts/release.sh` runs. Use them if the script fails
midway, or if you need to release without flo.

## Pre-flight

1. `git checkout main && git pull` — make sure local is current.
2. `git log --oneline vLAST..HEAD` — sanity-check what's shipping.
3. Build locally: `swift build -c release`. The release tarball is built from a tag, but it's worth knowing `main` compiles before you tag it.

## Bump version

Two files carry the version string. Update both to the new version:

- `Sources/Gitbar/Views/SettingsView.swift` — the "Gitbar X.Y.Z · Built for the menu bar" line in the Settings footer.
- `install` — the `VERSION="X.Y.Z"` constant used by the from-source installer's `Info.plist`.

Commit:

```
git add Sources/Gitbar/Views/SettingsView.swift install
git commit -m "bump to X.Y.Z"
```

> Branch protection on `main` requires PRs. Release commits (version bump + Homebrew formula update) currently bypass with maintainer credentials. If a release is being driven by someone without bypass rights, open a PR for both commits instead.

## Tag and push

```
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin main
git push origin vX.Y.Z
```

The push of the tag is what creates the GitHub source tarball at
`https://github.com/brunokiafuka/gitbar/archive/refs/tags/vX.Y.Z.tar.gz`.
The Homebrew formula consumes this URL, so the tag must be pushed before computing the sha256.

## Write release notes

Notes live in the GitHub release body, not in a `CHANGELOG.md`. Voice and structure for v0.1.1 / v0.2.0:

- One-sentence opener stating the shape of the release ("Two new filtering capabilities and a UI default change on the Review tab.").
- Group changes under `### New`, `### Fixes`, optionally `### Polish`.
- Each bullet leads with a bold one-liner and the issue/PR number, then 1–3 sentences of context. Mention what changed, what it replaces, and any migration behavior.
- Always close with an `### Upgrade` section:
  ```
  - Homebrew: `brew upgrade gitbar`
  - From source: `./install` rebuilds into `~/Applications/Gitbar.app`.
  ```

Drafting tip: walk the merged PRs since the last tag (`gh pr view <n> --json title,body`) and pull the user-facing summary from each PR's "What's in" section. Don't paste the test plan.

## Publish the GitHub release

```
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file /tmp/gitbar-vX.Y.Z-notes.md
```

The release page should now show the tarball and source zip as auto-attached assets.

## Update the Homebrew formula

`Formula/gitbar.rb` ships in this repo and is consumed by the tap
(`brew tap brunokiafuka/gitbar https://github.com/brunokiafuka/gitbar`).
After the tag is pushed, compute the sha256 of the GitHub-generated tarball:

```
curl -sL https://github.com/brunokiafuka/gitbar/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
```

Edit `Formula/gitbar.rb`:

- Bump the `url` to the new tag.
- Replace `sha256` with the value above.

Commit and push:

```
git add Formula/gitbar.rb
git commit -m "update Homebrew formula for vX.Y.Z"
git push origin main
```

Verify with `brew upgrade gitbar` on a clean machine if available.

## Verify

- The release page renders the notes correctly: https://github.com/brunokiafuka/gitbar/releases/tag/vX.Y.Z
- Open the app — the Settings footer reads "Gitbar X.Y.Z".
- The in-app version checker (runs every 24h) will surface the new release on existing installs within a day. To test sooner, restart the app while connected.

## Rollback

If a release ships broken:

1. Don't delete the tag — the Homebrew formula and existing installs reference it.
2. Cut a new patch release (`X.Y.Z+1`) with the fix.
3. If the broken tarball is so bad that nobody should install it, mark the GitHub release as a pre-release in the UI so the version checker (which queries `releases/latest`) skips it.
