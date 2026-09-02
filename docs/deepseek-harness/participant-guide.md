# DeepSeek Harness — participant guide

Self-serve, for real (updated 2026-09-02 — this used to be an
operator-only demo script when `dsh` was local-only; it's now exposed one
instance per team, and this is the actual handout). One-time setup per
browser, then one example prompt per track.

## Getting in

- **URL**: `https://team<N>.hack.gsbn.trade` — use your own team's number
  (e.g. team 3 → `team3.hack.gsbn.trade`).
- **Login**: your browser will show a plain username/password prompt
  (HTTP Basic Auth, not a page). Username is `team<N>` (e.g. `team3`);
  the password is the one shared with your team at kickoff, same
  passphrase as your team's bolt.diy instance
  (`build<N>.hack.gsbn.trade`) — one thing to remember for both.

## Before the first prompt (once per browser/session)

1. Open your team's URL and log in (above).
2. **Pick a preset.** New-session preset selection lives in the composer's
   agent/preset picker (next to where you'd pick a model) — choose the
   track you want from the four below instead of the default "标准模式
   /Standard". This is a one-time choice per session: switching later
   requires a fresh session (a session can only change preset before it's
   produced anything).
3. Now type a prompt. The agent will explore the data on its own, likely
   ask you one or two questions before doing serious work (that's expected
   — see each preset's own instructions), and may spawn a teammate you'll
   see reported in its replies.
   (The workspace itself — `/workspace`, with the four track data folders
   read-only under `/workspace/data` — is already set up for you; there's
   no "choose a workspace" step to do.)

## Downloading files the agent generates (index.html, reports, etc.)

The UI's own "open this file" button (the little file-open action next to
a generated file) **will not work** — it always fails with
`transport failure for /api/host.openPath: HTTP 403`. That's not a bug in
this deployment: DeepSeek Harness's own web app hard-restricts that
action to a real local desktop, on purpose, and there isn't one here (see
[README.md](README.md)'s Known quirks if you want the full why).

**To actually get a file the agent created**, go to:

```
https://team<N>.hack.gsbn.trade/files/
```

**The trailing slash matters** — `/files` (no slash) does not work; it
falls through to the app itself instead of the file browser and the page
will look broken/blank. `/files/` (with the slash) shows a plain,
clickable directory listing of your team's workspace — click into it to
view or download `index.html`, a generated `.md` report, or anything else
the agent wrote, including into subfolders it created.

This is your team's own workspace only — no other team's files are
reachable from it.

**Reminder to say out loud during a demo**: the data in `/workspace/data`
is synthetic — a plausible shape to explore, not real shipping records.
Every preset is instructed to say so in its own findings; if it ever
doesn't, that's worth flagging as a prompt bug.

**Web search: confirmed working.** `DEEPSEEK_API_KEY` is set and tested
live against DeepSeek's own API — see [README.md](README.md)'s "Web search
needs a second, different credential" section for how it was verified. If
it ever regresses to "no usable web provider is registered," that section
also has the two real gotchas found while setting this up (the proxy
sidecar needing its own recreate, and a zero-balance key failing with
`402` rather than an obvious auth error).

## Track 1 — Schedule Recovery Team

**Preset:** `Track 1 — Schedule Recovery Team`
**What it does:** investigates vessel/sailing/booking data for schedule
risk and recommends the edits that would recover it — spawning a
voyage/timing-risk teammate and a capacity/commercial-risk teammate when
the investigation warrants it.

> Our Shanghai–Singapore service keeps slipping and I don't know if it's a
> vessel problem or a booking problem. Look at the schedule and booking
> data, tell me where the real risk is, and recommend what I should
> actually change this week.

## Track 2 — Move Reconciliation Team

**Preset:** `Track 2 — Move Reconciliation Team`
**What it does:** the strongest "provable" consensus demo — spawns an
operator-view teammate and a crane-view teammate who independently compute
the same terminal move totals from different tables, then reconciles
whether the numbers actually agree.

> I don't trust our terminal performance numbers — the operator totals and
> the crane totals never seem to match anyone's expectations. Check
> whether they actually reconcile across a sample of calls, and if they
> don't, show me exactly where the gap is and what's driving it (delay,
> idle time, or something else).

## Track 3 — EDI Validator/Translator

**Preset:** `Track 3 — EDI Validator/Translator`
**What it does:** a single focused builder (not a debate team, on purpose
— the brief says pick one lane) for a COPRAR/BAPLIE validator, an
EDI-to-Excel converter, or an EDI-to-JSON translator.

> Our terminal UAT team spends weeks validating COPRAR and BAPLIE messages
> by hand. Build me a validator that takes one of these files and tells me
> exactly which segment and field is wrong and why — check it against the
> real SMDG code lists, not just the sample subset in the repo.

## Track 4 — Transshipment Reconciliation Team

**Preset:** `Track 4 — Transshipment Reconciliation Team`
**What it does:** the proof-of-concept — spawns a mainliner-view teammate
and a terminal-view teammate to reconcile disagreeing schedule data,
mirroring the track's own real premise that three stakeholders don't see
the same schedule.

> Our feeder connections keep slipping through the cracks and every
> system seems to show a different version of the schedule. Investigate
> our transshipment connections, figure out where the mainliner's and the
> terminal's view of reality actually diverge, and tell me which
> connections are genuinely at risk versus which are just noisy data.

## What "good" looks like, to watch for live

- The agent reads the track's `brief.md` before doing anything else (Plan
  Mode: explore first).
- It asks at least one real clarifying question rather than guessing scope.
- For Tracks 1/2/4, it visibly spawns at least one named subagent and
  reports back what that subagent found before writing a final answer.
- Any factual claim about SMDG/UN-CEFACT standards, port codes, or industry
  practice is something it looked up (`tool-web`), not invented.
- The final answer explicitly caveats that the underlying numbers are
  synthetic.
