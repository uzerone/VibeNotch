<p align="center">
  <img src="assets/icon.png" alt="VibeNotch app icon" width="400" height="400">
</p>

<h1 align="center">VibeNotch</h1>

> **Status — stabilizing.** VibeNotch is a personal-scale project that's settling down after a round of accuracy and reliability fixes (current release: 1.5.4). It's comfortable for daily use; a few rough edges remain and details may still shift between releases, so treat the billing figures as a close guide rather than the final word. Use it, and file issues.

A Dynamic-Island-style monitor for your AI coding agents — [Claude Code](https://claude.com/claude-code) and [OpenAI Codex](https://openai.com/codex) — pinned to the MacBook Pro notch.

Hidden when idle. Drops down a status line while Claude or Codex is running. Hover to expand the stats card. Or pin it to the system menu bar instead — your pick.

Requires macOS 13+. **No pre-built binary** — build from source with the scripts in [Build](#build) below. The DMG output lands at the project root.

## What's new in 1.5.4

- **Now lives in the menu bar too.** Don't want the pill near the notch? You can now show your usage right up in the menu bar instead — like "23% · 8:45 PM" — and click it to see the full details. Choose where it sits in Settings: the notch, anywhere on screen, or the menu bar.
- **Open it your way.** Pick whether the details card opens when you hover over it, or only when you click. Whatever feels right to you.
- **Easier to read at a glance.** The card is tidier, with clearer sections, and now shows how long until your usage resets — "2h 13m left · resets 8:45 PM" — right up front.
- **Always dark.** VibeNotch now sticks to one clean dark look, all the time.
- **Asks for permission just once.** After you allow access the first time, restarting your Mac won't make it ask again.

## 1.5.3

- The pill is better at showing when Claude or Codex is working, and when it's done.
- More accurate cost numbers for Codex.
- The pill no longer gets stuck off-screen — it always comes back where you can see it.
- Plus small fixes and tidying.

## 1.5.2

- VibeNotch finally has a **real app icon**. It runs quietly in the background with no Dock icon, but when you go looking for it — in Spotlight search or your Applications folder — it used to be a blank placeholder. Now it's the friendly notch face you see at the top of this page.

## 1.5.1

- Meet **Fable 5** — Anthropic's new flagship. VibeNotch now knows it by name, gives it its own flagship rose-pink dot, and prices it correctly at $10/$50 per million tokens.
- **Fixed a big cost bug:** Opus 4.5 and newer were being charged at the old Opus 4.1 rate ($15/$75), which overstated your Opus spend roughly threefold. Now every Claude model — including Opus 4.8 — uses its real current price, so the dollar figures actually add up.

## 1.5.0

- VibeNotch now watches **OpenAI's Codex** too, right alongside Claude. The one pill follows whatever you're working in — switch to Codex and it turns teal, shows **GPT-5.5**, and adds a chip for how hard it's thinking.
- No login or setup needed for Codex — it's all read from files already on your Mac. The **percentage** you've used (5-hour and 7-day, with reset times) is the exact figure OpenAI reports.
- One honest note: the Codex **dollar amount** is our own estimate from your token counts, so treat it as a ballpark, not a bill. The percentage is exact.

## 1.4.0

- The little dots that tell you Claude is working now look exactly the same whether you're peeking at the pill or have the full card open.
- A small note in Settings now tells you, in plain words, whether VibeNotch can see your Claude login — so you instantly know if the number you're looking at is the real one or just a guess.
- The "Launch at login" switch is now a friendly green when it's on, just like the switches in your Mac's regular Settings app.

## 1.3.0

- Everything moves more smoothly. Little dots pulse while Claude is thinking, a soft checkmark appears when Claude is waiting for you, and the pill politely tucks itself away once you've seen it.
- New colors for each Claude — purple for Opus, blue for Sonnet, mint green for Haiku.
- Easier-to-read numbers — your spending today is shown big and bold up top, tokens and dollars sit side by side, and the bar turns orange as you get close to your limit.
- The little gray dot that used to sit there doing nothing is gone.
- The frosted-glass look and the speed-of-spending panel were removed — they weren't doing much.

## 1.2.0

- **Free mode** — you can now drag the pill anywhere on your screen, instead of being stuck under the notch.
- You can see which Claude you're using — Opus, Sonnet, or Haiku — and how much each one is costing you.
- A new panel showing how fast you were burning through your budget (later removed in 1.3.0 because it wasn't actually that useful).
- Things feel a bit snappier, and a few small bugs were fixed.

## 1.1.0

- The number on the pill now matches exactly what you see when you type `/usage` inside Claude Code, or look at your "Plan usage" on claude.ai. Before this, it was just a guess.

## 1.0.0

- The very first version — a tiny pill under your Mac's notch that takes a rough guess at how much of Claude you've used today.

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
