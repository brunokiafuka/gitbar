# gitbar

A native macOS menu bar app for tracking the pull requests and issues that need your attention. Implemented in Swift (SwiftUI + AppKit, borderless floating panel).

## What it does

Click the menu bar icon to open a 440 × 580 panel with tabs:

- **All** — everything at a glance
- **Mine** — PRs you authored that are still open
- **Review** — PRs awaiting your review
- **Issues** — issues assigned to you
- **Stats** — KPI grid

Rows show title, repo, status chips, PR number, and last-updated time. Clicking a row opens the PR/issue in your browser.

## Authentication

Uses a **GitHub Personal Access Token** (classic `ghp_…` or fine-grained `github_pat_…`) read only from:

`~/.gitbar/config.json` → `github.token` (written by the Settings window or by hand)

Example `~/.gitbar/config.json`:

```json
{
  "github": {
    "token": "ghp_xxxxxxxxxxxxxxxxxxxx"
  }
}
```

(Fine-grained tokens look like `github_pat_…` — same key.)

The app creates `~/.gitbar/` on first save. If you used an older path (`~/.flo/config.json`), copy the `github` object into `~/.gitbar/config.json`.

### Creating a token

**Classic (simplest):** open [Create new token (classic)](https://github.com/settings/tokens/new?description=Gitbar&scopes=repo) — the note and **repo** scope are pre-selected; generate and paste into Gitbar Settings.

**Fine-grained:** open [Create fine-grained token](https://github.com/settings/personal-access-tokens/new?name=Gitbar&description=Gitbar%20menu%20bar%20app), choose repository access, then under **Repository permissions** set at least:

- **Pull requests** — Read and write (merge)
- **Issues** — Read
- **Metadata** — Read

Paste the token into Gitbar Settings (gear in the tab bar): use **Paste**, **⌘V**, or the context menu — the field uses a native control so clipboard paste works reliably. Saving writes `~/.gitbar/config.json`.

## Data sources

All via the [GitHub REST API](https://docs.github.com/en/rest) using the token:

| Query           | Endpoint                                                       |
| --------------- | -------------------------------------------------------------- |
| My open PRs     | `GET /search/issues?q=type:pr+state:open+author:@me`           |
| Review requests | `GET /search/issues?q=type:pr+state:open+review-requested:@me` |
| Assigned issues | `GET /search/issues?q=type:issue+state:open+assignee:@me`      |
| PR review state | `GET /repos/{owner}/{repo}/pulls/{number}/reviews`             |

## Prerequisites

- macOS 14 or later
- Swift toolchain (comes with Xcode Command Line Tools: `xcode-select --install`)
- A GitHub PAT

## Install

```bash
git clone https://github.com/brunokiafuka/gitbar.git
cd gitbar
./install
open "$HOME/Applications/Gitbar.app"
```

The installer builds a release binary, wraps it in a `.app` bundle with `LSUIElement = true` (no Dock icon), and drops it in `~/Applications`.

## Project layout

```
gitbar/
├── Package.swift
├── Sources/Gitbar/
│   ├── App.swift            # NSApplicationDelegate, NSStatusItem, floating NSPanel
│   ├── Theme.swift          # colors, fonts, NSVisualEffectView wrapper
│   ├── Config.swift         # token resolution + save
│   ├── GitHub.swift         # REST client + Codable models
│   ├── Store.swift          # ObservableObject state
│   └── Views/
│       ├── PanelView.swift    # panel with tabs
│       ├── Rows.swift         # PR row, issue row
│       ├── Chips.swift        # status chips, label pills, section headers
│       ├── StatsView.swift    # KPI grid
│       ├── TokenField.swift   # AppKit token field (paste-friendly)
│       └── SettingsView.swift # token, notifications, refresh interval
├── install                  # builds + installs the .app
└── README.md
```

## Status

MVP. The UI follows the Gitbar design (Liquid Glass material, Raycast-style tabs and chips). Known gaps vs. the full design:

- Merge / mark-ready actions are not wired yet (`PUT /repos/.../merge`, `markPullRequestReadyForReview`).
- Failing-CI section requires the checks API (`GET /repos/.../commits/.../check-runs`) — currently omitted.
- Stats are derived from the current fetch (open counts) rather than merged/reviewed over time.
