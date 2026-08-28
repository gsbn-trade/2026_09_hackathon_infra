# Track 2 · Terminal Operations — Dataset Brief

A synthetic **Terminal Performance dataset** modelled on a terminal departure
report (TDR) as produced by container terminals / shipping-line systems for a
set of vessel calls at 8 Asia-Pacific ports. It mirrors the structure of the
Hapag-Lloyd `RH_TD*` data model (tables `TDAMPF_sched` … `TDCRANE`/`TDDELAY`
plus a Key-Figures workbook).

## What this is

- **110 physical vessel calls** at real UN/LOCODE ports and real (SMDG)
  terminal codes, dated June 2026, spread across 8 ports.
- Identifiers (vessel names + IMO numbers, SMDG terminal codes, container
  operator codes, delay-reason codes) are **real**.
- The **operational numbers are synthesised** — that is, this is not real
  production performance data. No single move count, timestamp, or delay
  figure corresponds to an actual operation. Treat it as a realistic,
  internally-consistent sample for building and comparing analyses.

## What a TDR is

For every vessel call, a terminal/system records:

1. **Planned vs actual berth window** — when the vessel was *scheduled* to
   arrive/depart versus when it *actually* did.
2. **Work phases** between berth and unberth: lashing gang on/off, first crane
   lift to last crane lift.
3. **Moves** — every container move (and hatch cover) performed, accountable
   by container operator *and* by crane.
4. **Crane deployment** — the time window each quay crane actually worked.
5. **Delays** — every delay, its reason code, its duration, and whether it is
   charged to the terminal (`T`), the vessel (`V`), or is unrestricted.

The relationships between the figures are load-bearing: a well-formed report
reconciles every level of detail to the same totals.

## Files

| File | Contents | Grain |
|---|---|---|
| `tdr_terminal_call.csv` | One row per physical vessel call: port (UN/LOCODE), terminal (SMDG code + name), vessel (name, IMO, operator), size class, nominal TEU, planned vs actual arrival/departure, gross port hours, cranes used | 1 row = 1 call |
| `tdr_header.csv` | The timing summary for each call: planned/actual times, lashing on/off, first/last crane lift, **gross vs net shift time**, **gross vs net hours worked**, total/container/hatch-cover moves | 1 row = 1 call |
| `tdr_move_summary.csv` | Every move, split three ways (summary type `O`=by container operator, `C`=by crane, `V`=vessel/hatch-cover subtotal), with dimensions: move type (load/discharge/restow/…) | many rows = 1 call |
| `tdr_crane_deployment.csv` | Per crane, the window it worked (first lift → last lift) | 1 row = 1 crane on 1 call |
| `tdr_delay.csv` | Every delay: reason code, free-text hint, duration (hrs), and whether it's a crane-level or vessel-level delay | 1 row = 1 delay |
| `tdr_delay_reason.csv` | The delay-reason code catalog (codes + responsibility `T`/`V`/blank) | reference |

## How the figures connect

**Timing.** For each call:

- `gross_port_time` = actual departure − actual arrival.
- `gross_shift_time` = last crane lift − first crane lift (the working window).
- `net_shift_time` = `gross_shift_time` − the vessel-level delays on that call.
- `gross_hours_worked` = Σ over cranes of (crane's last lift − crane's first lift).
- `net_hours_worked` = `gross_hours_worked` − the crane-level delays.

So the gap between gross and net figures is **delay**, and it is attributable:
vessel-level delays come out of shift time, crane-level delays come out of
hours worked.

**Moves.** For every call, the same total reconciles across all three summary
types:

```
sum(operator rows, container) + hatch-cover moves = total moves
sum(crane rows, total moves)                       = total moves
```

That is: the vessel total = Σ operator row moves = Σ crane row moves.

**Idle.** Because a call spans arrival→departure but lifting only spans
first→last lift, the difference between gross-port time and gross-shift time
is berth idle (time when the vessel was alongside but no crane was working).
This, net of delays, is one of the most direct signals in the dataset.

## Relationship notes

- **Key:** `ID_NUMBER` in `tdr_terminal_call.csv` is the primary key for a
  call; it is the foreign key `FK_TERMINAL_CALL` in the other tables, and it
  also appears as `ID_NUMBER` in `tdr_header.csv` and `tdr_delay.csv`.
- `tdr_header.csv` and `tdr_move_summary.csv` both carry `REL_NUMBER` (report
  version) and `VALIDITY_FLAG`. All rows are version 1 / valid (`Y`); the
  column is present because in real TDR data a call can have multiple report
  versions as corrections accumulate.
- `tdr_delay_reason.csv` is the canonical catalog: `DRC_CODE` → `RESPONSIBILITY`
  (`T` terminal / `V` vessel / blank unrestricted). `tdr_delay.csv` should only
  reference codes present here.
- Container operators are coded with their real SCAC-equivalent codes (e.g.
  `MSK`, `MSC`, `ONE`, `OOL`); a move may be coded to the operating carrier, so
  many operators can share one call.

## Notes for reading the data honestly

- **Planned vs actual.** Some calls arrived **early** (actual < planned) rather
  than merely on time or late; don't assume the sign of the variance.
- **Delays are only on some calls.** Most calls run clean; delays are present
  but not universal — this is what makes gross-shift ≠ net-shift visible only
  where it should be.
- **Different vessels, different scale.** Feed/regional calls (fewer cranes,
  fewer moves) and 24k-TEU mainliners (8–9 cranes, >10k moves) sit in the same
  table. Compare like-for-like.
- The data is **synthetic operational numbers on real identifiers** — treat
  every absolute figure as a representative sample, and rely on the
  *relationships* (reconciliation, delay attribution, net-vs-gross) rather than
  any single value.

## Suggested starting points (you choose)

The strongest fields here are the **reconciled timing/delay/move structure**,
the **net-vs-gross machinery**, and the **planner-vs-actual split across
ports/terminals/vessel classes**. How you want to cut, aggregate, or model it
is up to you — the data is shaped so that the same totals can be reached from
several angles (operator, crane, port, vessel class, delay responsibility) and
should cross-check whichever way you slice it.