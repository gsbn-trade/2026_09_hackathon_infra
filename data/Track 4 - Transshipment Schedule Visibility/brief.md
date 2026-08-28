# Track 4 — Schedule Visibility in Transshipment
## Field Briefing (read this first)

**The job in one line:** a transshipment connection only works if the three stakeholders — the **mainliner** (long-haul mother vessel), the **feeder operator** (regional distributor), and the **terminal operator** (the hub where boxes move from one ship to the other) — all see the *same* vessel schedule, at the *same time, with the same identifiers*. They do not. Your job is to expose and quantify how badly they disagree, and what breaks because of it.

**Where this comes from:** the SMDG/UN-CEFACT White Paper on Transshipment (Nov 2025) names **limited visibility of vessel schedules across Mainliner, Feeder, and Terminal** as one of the major pain points. Concretely:

1. **They don't even name the same voyage the same way.** A vessel's voyage number is assigned by its operator — but VSA partners, slot charterers, and terminals each re-key the *same* physical voyage under their own codes. There is no universally-issued **Terminal Call ID** (today it's a composite of port + terminal + vessel + voyage/ETA — which breaks whenever any component changes). The terminal's own system may not even carry a code for a call at all, using a blank instead of a dummy LOCODE.

2. **Each stakeholder plans on a different horizon.** Mainliners publish 12–16 weeks out. Feeders plan 3–4 weeks out. Terminals start berth alignment ~7 days out and *freeze* changes in the 24–48 hours before arrival. So a schedule edit lands at different times in each stakeholder's world.

3. **Updates travel by email and Excel.** A real-time, event-driven update pipeline is the paper's stated fix (§6.5), but today a change is announced (not streamed) — so there's inherent **latency**: the same voyage's ETA updates on the mainliner's site at one moment, the feeder's site later, the terminal's site latest (or not at all if it's frozen).

4. **A schedule change can break a connection.** Transshipment feasibility has formal categories — **Good / Tight / Overlapping / Missed** — defined by the gap between the inbound vessel's arrival and the outbound's departure. A stable connection can slip to Tight or Missed purely from ETA drift. The paper's proposed fix is a **Unique Connection ID (UCID)** — a stable identifier for the *connection between two terminals on a date*, independent of which specific vessel is assigned — so a swapped vessel or rebooked connection keeps its identity instead of going dark.

**A typical problem day** — you're monitoring 30+ connections on a Monday. The mother vessel that should feed three feeder loops is 6 hours late and its VSA partner republished the ETA before you saw the operator's own update. One connection is now technically infeasible (published schedule says the feeder left before the mother arrives). Another terminal's voyage code got reused across two different physical voyages. Which connection is about to miss? Who *didn't* get the memo?

**What a good hack would do:** turn scraped multi-source schedule histories into a **single reconciled, event-streamed truth** — align the identifiers, compute per-source update latency and cadence, flag stale or impossible updates before they ripple, and predict which transshipment connections are about to slip from the *timing* of ETA changes alone. That's exactly the white paper's §6.1–6.5 agenda.

## Data files

All timestamps are **ISO 8601, UTC**. Vessel/service/voyage identifiers are fictional but use real formats (IMO 7-digit, UN/LOCODE 5-char, SMDG-style terminal codes).

| File | What it is | The question it answers |
|---|---|---|
| `port_calls.csv` | Ground truth: every voyage's hub call — scheduled vs actual ETA/ETD, total delay | what *really* happened |
| `identifiers_map.csv` | The alignment trap: the same physical voyage, under the voyage codes / terminal logic / LOCODEs each of the 3 sources uses | *which physical call* is this, really? |
| `schedule_updates.csv` | **The core.** Every update event to a voyage/port-call ETA as *published by each source*, with its own timestamp and ETA before→after | latency (Q1), cadence (Q2), timing-to-arrival (Q3), ETA drift (Q4) |
| `connections.csv` | Transshipment connections classified **Good / Tight / Overlapping / Missed** (schedule vs actual), UCID refs, rebook/driver markers | does drift break the connection? |
| `sources.csv` | The stakeholders + their crawl / publication metadata (first-seen latency, cadence, freeze window) | the scraping simulation |

## ⚠️ Two deliberate data defects (the tolerance test)

This track's data is *not* uniformly clean — that's the point. Two planted defects, one per file; **a good team catches them rather than passing them through.**

1. **`schedule_updates.csv`: one impossible timestamp.** A terminal update for a vessel that's *published after that vessel already arrived* — a chronologically impossible row (the terminal should have frozen). If your pipeline doesn't catch it, you compound a real scraping artifact.
2. **`identifiers_map.csv`: one reused identifier.** One terminal voyage code is reused across **two different physical voyages** (the §5.1 reuse trap — happens when no issued Terminal Call ID exists). If you join on the wrong key, you silently merge two different ships' calls.

The brief tells you they exist; finding *which rows* and *defending against them* is the build.

## One real-world texture

Shanghai (Yangshan) runs the world's largest automated terminal — yet even there, terminals, mainliners, and feeders each publish their own ETA and the reconciliation is manual. The real pain is never data scarcity; it's that three versions of "the schedule" quietly disagree, on different clocks, under different identifiers, until a missed feeder connection makes it everyone's problem. Your dummy data recreates exactly this tension.

**Data-quality note:** figures are structural, not audited — they exist to force the reconciliation/visibility problem into existence, and every number cross-checks against `port_calls.csv` ground truth.