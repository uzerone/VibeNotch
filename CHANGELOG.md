# Changelog

All notable changes to VibeNotch, newest first. The latest release is also summarized in the [README](README.md).

## 1.9.0

- **Centered and compact.** The session % and today's spending now sit centered on the card, and the card sizes itself to what it's showing instead of holding empty space.
- **One bar, both answers.** Each model's share is drawn right into the session bar in its own color — no separate breakdown block.

## 1.8.0

- **Moves like the real Dynamic Island.** The card grows out of the notch with a gentle bounce and folds back in when you're done.
- **Shaped to your notch.** The pill hugs your Mac's actual notch, and the open card's top corners curve inward to meet it — like they're one piece.
- **Easier to read at a glance.** The session % is the clear star, today's spending sits on one tidy line, and Settings now looks Mac-native — System-Settings-style pickers and switches, and a quieter Quit button.
- **Clicks land right even mid-animation**, and Reduce Motion quietly turns it all into a simple fade.

## 1.7.1

- **No more nagging orange banner.** Brief hiccups fetching the official usage figure (rate limits, network blips) are now retried quietly in the background — the warning only appears when there's something you can actually fix, like an expired login.
- **The bottom model bar isn't cut off anymore.** The card now grows to fit the warning line instead of squeezing the "Session by model" bar off the edge.

## 1.7.0

- **The pill is always reachable.** It no longer vanishes when idle — it blends into the notch (or dims in free mode), so hover or click always works.
- **"Done" means done.** No more green checkmark while a long task is still running.
- **A small "×2" badge** shows when you're running more than one session at once.
- **Honest numbers.** If the official usage figure can't be fetched, the card says so and quietly retries on its own.
- **The menu-bar pop-up now matches the card.** Same layout, same numbers, weekly gauge included.
- **Lighter on your Mac.** Less background work, less memory, and countdowns keep ticking on their own. Times also follow your 12/24-hour clock setting.
- **Fixed a rare crash** in the display-picker window.

## 1.6.1

- **Steadier menu bar.** The menu-bar reading no longer wiggles left and right as the numbers and time change — it now holds its place.
- **Consistent pop-up size.** Opening Settings from the menu-bar pop-up no longer makes the window jump to a different width.

## 1.6.0

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
