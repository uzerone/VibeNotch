<p align="center">
  <img src="assets/icon.png" alt="VibeNotch app icon" width="400" height="400">
</p>

<h1 align="center">VibeNotch</h1>

> **Status — stabilizing.** VibeNotch is a personal-scale project that's settling down after a round of design and reliability work (current release: 1.9.0). It's comfortable for daily use; a few rough edges remain and details may still shift between releases, so treat the billing figures as a close guide rather than the final word. Use it, and file issues.

A Dynamic-Island-style monitor for your AI coding agents — [Claude Code](https://claude.com/claude-code) and [OpenAI Codex](https://openai.com/codex) — pinned to the MacBook Pro notch.

Hidden when idle. Drops down a status line while Claude or Codex is running. Hover to expand the stats card. Or pin it to the system menu bar instead — your pick.

Requires macOS 13+. **No pre-built binary** — build from source with the scripts in [Build](#build) below. The DMG output lands at the project root.

## What's new in 1.9.0

- **Centered and compact.** The session % and today's spending now sit centered on the card, and the card sizes itself to what it's showing instead of holding empty space.
- **One bar, both answers.** Each model's share is drawn right into the session bar in its own color — no separate breakdown block.

Older versions are in the [changelog](CHANGELOG.md).

## First launch — please click "Always Allow"

The first time you open VibeNotch, a little window will pop up from your Mac asking if VibeNotch can look at your Claude login.

**Please click the "Always Allow" button.**

That's it. VibeNotch can now show you the exact same usage percentage you see inside Claude Code and on claude.ai.

A few things worth knowing:

- **Why two buttons?** "Allow" only works for one launch — so the window will pop up again next time you open VibeNotch, and the time after that, and so on. "Always Allow" means you only have to do this once.
- **Is it safe?** Yes. VibeNotch only uses your login to ask Anthropic "how much have I used this month?" — the same question Claude Code asks. Your login never goes anywhere else, and VibeNotch doesn't send any data to anyone but Anthropic.
- **What if I click "Deny"?** VibeNotch still works — it just shows a rough guess of your usage based on local files instead of the exact number from Anthropic.

### Want "Always Allow" to stick when you update VibeNotch?

If you don't do anything special, every new version of VibeNotch will look like a brand-new app to your Mac, so the "Always Allow" prompt will come back every time you update.

To fix this, open Terminal **once** and run:

```sh
./scripts/setup-signing-identity.sh
```

You only ever need to run this once. After that, click "Always Allow" the next time the prompt shows up, and you'll never see it again — even when you install a newer version of VibeNotch.

## Build

```sh
swift run -c release          # run from source
./scripts/build-dmg.sh        # rebuild the .dmg
```
