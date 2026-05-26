# CC Island

> **Status — in active development.** CC Island is a personal-scale project that's still being shaped. Expect breaking layout changes, occasional bugs, and feature churn between releases. Use it, file issues, but don't depend on it as a stable measurement of your Anthropic billing.

A Dynamic-Island-style monitor for [Claude Code](https://claude.com/claude-code), pinned to the MacBook Pro notch.

Hidden when idle. Drops down a status line while Claude is running. Hover to expand the stats card.

Requires macOS 13+. **No pre-built binary** — build from source with the scripts in [Build](#build) below. The DMG output lands at the project root.

## What's new in 1.4.0

- The status indicator (three pulsing dots) now looks the same in the dropdown and in the expanded card — no more visual mismatch between the two views.
- A new badge in Settings tells you whether CC Island can see your Claude login, so you know straight away if the percentage shown is the real number from Anthropic or a local estimate.
- The "Launch at login" switch is a clean green-when-on toggle, matching the way switches look in macOS System Settings — regardless of your accent color.

## 1.3.0

- Smoother motion: pulsing dots while Claude is working, a soft checkmark when it's waiting on you, and the pill quietly tucks away once you've seen it.
- Fresh model colors — purple for Opus, blue for Sonnet, mint green for Haiku.
- Cleaner numbers: a hero "today's spend" line, side-by-side tokens and dollars in the session row, and a progress bar that warms up to amber as you approach your limit.
- No more clutter when nothing's happening — the idle gray dot is gone.
- Removed the glass/tinted appearance options and the burn-rate panel.

## 1.2.0

- **Free mode** — drag the pill anywhere on screen instead of pinning it to the notch.
- See which models you're using — Opus / Sonnet / Haiku — and how much each costs you per session.
- Burn rate panel (removed in 1.3.0 — it wasn't actually helpful).
- Speed-ups and small fixes.

## 1.1.0

- The pill now shows the same usage percentage you see in Claude Code's `/usage` and on claude.ai, by reading your existing Claude login.

## 1.0.0

- First version — a small pill under the notch that estimates token usage from local Claude Code files.

## First launch — please choose "Always Allow"

The first time you open CC Island, macOS will show a **Keychain access prompt** asking permission for "CC Island" to read the `Claude Code-credentials` item.

> **Click "Always Allow".**
> If you click "Allow" once, macOS will re-prompt every launch — annoying. "Always Allow" is the same trust level you already gave Claude Code itself.
> If you click "Deny", CC Island still runs but the hero percentage falls back to a local token estimate instead of the exact figure Anthropic reports.

CC Island uses your existing Claude Code login to call Anthropic's plan-usage endpoint — the same data Claude Code's `/usage` command and claude.ai's "Plan usage" panel display. **Your token never leaves your machine except to `api.anthropic.com`.** No telemetry, no other network calls.

## Build

```sh
swift run -c release          # run from source
./scripts/build-dmg.sh        # rebuild the .dmg
```
