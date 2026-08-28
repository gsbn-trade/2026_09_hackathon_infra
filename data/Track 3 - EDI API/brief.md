# Track 3 — EDI / Data Exchange
## Field Briefing (read this first)

**Who this track is for:** teams whose "customers" are the people who run carrier↔terminal data exchange every day — the UAT engineers, integrators, and terminal operators who live in EDIFACT.

### The pain

Carrier and terminal teams told us exactly where it hurts, and it's not parsing:

- **UAT is the longest phase.** When a terminal, carrier team, or authority takes on a new EDI message, the time goes into *validating*: is the syntax right, are the codes legal, are the semantics consistent, is the message truthful against the vessel schedule? A tool that automates **syntax + semantic validation** is what they'd actually use.
- **The most useful deliverable is validation and translation** — a tool that verifies a message and turns it into something a human or system can act on. (A "code assistant" is nice-to-have, but only helps where a counterparty hasn't built one already; validation and translation help everywhere.)
- **The silent reality: a lot of the world works in Excel.** Terminals — and even some carrier teams — genuinely can't generate EDI because their operation runs on spreadsheets. A tool that converts EDI (COPRAR / BAPLIE) into Excel with *customizable* columns and layout is a powerful, sellable thing.

### Focus messages — use these, not the whole standard

**BAPLIE and COPRAR are the most exchanged messages between carriers and terminals** (and some authorities request them too). Build against these two:
- **COPRAR** — Container Discharge/Loading *Order*: the carrier tells the terminal which containers to discharge or load at this port call, with equipment, size/type, and detail. A `BGM+45` message is a **loading** order; `BGM+43` is a **discharge** order.
- **BAPLIE** — Bay Plan / Stowage Plan: where each container sits on the vessel (7-digit `bay/row/tier` cell, e.g. `0020082`) — the master picture of the vessel's stowage.

Keep deliberately **out of scope** so teams don't drown: customs messages (CUSCAR), the full EDIFACT directory, and other message versions. Target **COPRAR + BAPLIE**, one directory version (**D.95B**, `UNOA:2` syntax), valid codes.

### Where first-time builders get it wrong (what a validator must catch)

The most common mistakes are **semantics** — required fields missing and invalid code values. A good validator catches three classes of failure:

1. **Syntax** — segment/terminator errors, malformed `UNH`/`BGM`.
2. **Code validity** — an invalid ISO 6346 size/type (e.g. `52G1`), a bad container check digit, an unknown action code, a non-UN/LOCODE port (e.g. `ZZZ`).
3. **Semantic consistency** — a date with no century, a stowage cell double-booked or out of range, a port that contradicts the voyage, a discharge record that says load.

Automated code application — flagging *and* auto-correcting the fixable ones — is explicitly valuable.

### The smart fix that makes validation tractable

Don't build a validator against the raw standard in a vacuum. The authoritative code lists and message definitions are **public** — see the SMDG implementation guides and code lists (smdg.org) for COPRAR and BAPLIE. A validator that checks against those canonical lists — rather than hard-coded guesses — is the one that survives contact with the real world.

### What a good hack would do

Pick ONE, build it well:

1. **A validator** for COPRAR/BAPLIE — `file in → syntax + semantic report`: which segment, which element, *why* it fails, and a suggestion. Bonus: auto-fix the auto-fixable.
2. **An EDI ↔ Excel converter** (COPRAR/BAPLIE in; readable, customizable output) — with configurable column names and layout, because that's the real ask from teams that live in Excel. (Can embed a validator to flag bad rows.)
3. **A translator** EDI → canonical JSON/REST model (`port_call_journal.json`) that fails loudly on bad input instead of guessing.

All three share one core: **parse the standard reliably, validate it, and translate it cleanly.** That's the lane.

## Data files

| File | What it is |
|---|---|
| `samples/COPRAR_20260801.edi` | Valid COPRAR **loading** order — Shanghai arrival, 10 containers (D.95B) |
| `samples/COPRAR_SEMANTIC_ERRORS.edi` | Same shape with **built-in defects** to catch (bad code, check digit, date, port) |
| `samples/BAPLIE_20260801.edi` | Valid BAPLIE bay plan with stowage cells |
| `samples/BAPLIE_SEMANTIC_ERRORS.edi` | Bay plan with **defects** (double-booked cell, out-of-range bay, invalid code) |
| `smdg_code_lists.csv` | Compact working subset: ISO 6346, message types, qualifiers, UN/LOCODE — a starting point; use the canonical SMDG lists for full coverage |
| `edi_to_excel_map.csv` | EDI segment → Excel column mapping + customization notes (for the converter tool) |
| `port_call_journal.json` | Canonical JSON target model your API should emit after validating + translating |

## One real-world texture

A single Shanghai port call on a master vessel publishes **COPRAR** to the terminal for 10–12k containers and **BAPLIE** for the whole stow — and the terminal must validate both before the berth operation starts. That's a thousands-of-records, minutes-long validation gate on every arrival. Automating that gate — not the parsing — is the actual prize.
