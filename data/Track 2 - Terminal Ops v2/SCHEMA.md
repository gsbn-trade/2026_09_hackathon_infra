# Track 2 · Terminal Ops v2 — Column-by-Column File Schema

Reference for the six CSV files that make up the Track 2 dataset. For the
overview, relationships, and reading notes, see `brief.md` alongside this file.

---

## 1. `tdr_terminal_call.csv` — 110 rows (one per vessel call)

| # | Column | Type | Example | Notes |
|---|--------|------|---------|-------|
| 1 | `ID_NUMBER` | int | `0` | Primary key for the call. Joins to `FK_TERMINAL_CALL` elsewhere. |
| 2 | `PORT_LOCODE` | str (UN/LOCODE) | `KRPUS` | 5-char port code. 8 distinct ports. |
| 3 | `SMDG_CODE` | str | `BNCT` | SMDG terminal code for the specific terminal at that port. 14 distinct. |
| 4 | `TERMINAL` | str | `BUSAN NEW CONTAINER TERM` | Human-readable terminal name. |
| 5 | `VESSEL_NAME` | str | `MAERSK MC-KINNEY MOLLER` | Real vessel name. 11 distinct. |
| 6 | `IMO` | str (7-digit) | `9619907` | IMO ship number. Real, matches vessel. |
| 7 | `OPERATOR` | str (BIC) | `MSK` | Vessel's operating carrier. 7 distinct. |
| 8 | `SIZE_CLASS` | str | `ULCV` / `NEO` / `WIDEBEAM` | 3 distinct vessel-size classes. |
| 9 | `NOMINAL_TEU` | int | `17800` | Vessel nominal capacity (TEU). 14,000–24,100. |
| 10 | `PLAN_ARR` | datetime | `2026-06-01 04:24` | Scheduled arrival. |
| 11 | `PLAN_DEP` | datetime | `2026-06-02 09:03` | Scheduled departure. |
| 12 | `ACT_ARR` | datetime | `2026-06-01 06:52` | Actual arrival. |
| 13 | `ACT_DEP` | datetime | `2026-06-02 00:43` | Actual departure. |
| 14 | `GROSS_PORT_HRS` | float | `17.84` | `ACT_DEP − ACT_ARR`, hours. Range 16.19–45.69. |
| 15 | `CRANES` | int | `5` | Quay cranes used on this call. Range 2–9. |
| 16 | `NFLEET_CRANES` | int | `9` | Rated crane capacity of the terminal (in fleet). |

---

## 2. `tdr_header.csv` — 110 rows (timing summary, one per call)

| # | Column | Type | Example | Notes |
|---|--------|------|---------|-------|
| 1 | `ID_NUMBER` | int | `0` | FK → `tdr_terminal_call.ID_NUMBER`. |
| 2 | `REL_NUMBER` | int | `1` | Report version. All `1` in this release. |
| 3 | `VALIDITY_FLAG` | str | `Y` | Valid / superseded. All `Y`. |
| 4 | `LOCODE` | str | `KRPUS` | Port (UN/LOCODE). |
| 5 | `TERMINAL_CODE` | str | `BNCT` | SMDG terminal code. |
| 6 | `PLAN_ARR` | datetime | `2026-06-01 04:24` | As scheduled. |
| 7 | `PLAN_DEP` | datetime | `2026-06-02 09:03` | As scheduled. |
| 8 | `ACT_ARR` | datetime | `2026-06-01 06:52` | Actual. |
| 9 | `ACT_DEP` | datetime | `2026-06-02 00:43` | Actual. |
| 10 | `LASHGANG_ON` | datetime | `2026-06-01 07:27` | Lashing gang started. |
| 11 | `LASHGANG_OFF` | datetime | `2026-06-01 23:50` | Lashing gang finished. |
| 12 | `FIRST_CRANELIFT` | datetime | `2026-06-01 07:47` | First crane lift. |
| 13 | `LAST_CRANELIFT` | datetime | `2026-06-01 23:32` | Last crane lift. |
| 14 | `GROSS_SHIFT_TIME` | float (hrs) | `15.74` | `LAST_CRANELIFT − FIRST_CRANELIFT`. |
| 15 | `NET_SHIFT_TIME` | float (hrs) | `15.74` | `GROSS_SHIFT_TIME − Σ vessel-level delays`. |
| 16 | `GROSS_HOURS_WORKED` | float (hrs) | `50.14` | Σ per-crane work windows. |
| 17 | `NET_HOURS_WORKED` | float (hrs) | `48.01` | `GROSS_HOURS_WORKED − Σ crane-level delays`. |
| 18 | `TOTAL_MOVES` | int | `9705` | Container + hatch-cover moves. |
| 19 | `CONTAINER_MOVES` | int | `9388` | Container moves only. |
| 20 | `HATCH_COVER_MOVES` | int | `317` | Hatch-cover moves only (incl. restows). |
| 21 | `CRANES` | int | `5` | Quay cranes used (mirrors terminal_call). |

**Relationship:** `TOTAL_MOVES = CONTAINER_MOVES + HATCH_COVER_MOVES`.

---

## 3. `tdr_move_summary.csv` — 3,227 rows (moves, three-way split)

| # | Column | Type | Example | Notes |
|---|--------|------|---------|-------|
| 1 | `ID_NUMBER` | int | `0` | FK → call. |
| 2 | `REL_NUM` | int | `1` | Report version. |
| 3 | `CL_SUMMARY_TYPE` | str | `O` / `C` / `V` | **`O`**=by operator; **`C`**=by crane; **`V`**=vessel subtotal / hatch-cover. |
| 4 | `CTR_OPERATOR_BIC` | str | `WHL` | Container operator (BIC), populated when type=`O`. 11 distinct. |
| 5 | `CRANE_ID` | str | `Q01` / (blank) | Crane, populated when type=`C`. |
| 6 | `NO_OF_MOVES` | int | `354` | Move count for this row. Range 1–993. |
| 7 | `MOVE_DESCRIPTION` | str | `LOAD_FUL_45` | Concatenation of type/size/status, e.g. `{TYPE}_{EMPTY}_{SIZE}`. |
| 8 | `TYPE_OF_MOVE` | str | `LOAD`/`DISC`/`RDR`/`RSOB`/`TSM` | Load / discharge / restow / shift-on-board / transshipment. |
| 9 | `EQ_TYPE` | str | `CN` / `HCV` / (blank) | **`CN`**=container; **`HCV`**=hatch cover. |
| 10 | `CONTAINER_SIZE` | int | `45` | 20 / 40 / 45. Blank on hatch-cover and crane-total rows. |
| 11 | `EMPTY_FULL` | str | `FUL` / `MT` / (blank) | Empty or full. |
| 12 | `DEEP_SHORT_SEA` | str | `D` / `S` / (blank) | Deep-sea or short-sea voyage. |
| 13 | `TRANSHIPMENT_FLAG` | str | `Y` / (blank) | Transshipped cargo. |
| 14 | `FK_TERMINAL_CALL` | int | `0` | FK → `tdr_terminal_call.ID_NUMBER`. |
| 15 | `FK_TDR_REL` | int | `1` | FK → report version. |

**Reconciliation within a call:** Σ operator rows (container) + hatch-cover rows = Σ crane rows = total moves.

---

## 4. `tdr_crane_deployment.csv` — 457 rows (one per crane per call)

| # | Column | Type | Example | Notes |
|---|--------|------|---------|-------|
| 1 | `REL_NUM` | int | `1` | Report version. |
| 2 | `CRANE_ID` | str | `Q01` | Quay-crane identifier. 9 distinct. |
| 3 | `CRANE_TYPE` | str | `GC` | Gantry crane (all `GC`). |
| 4 | `FIRST_LIFT` | datetime | `2026-06-01 12:41` | Crane's first lift. |
| 5 | `LAST_LIFT` | datetime | `2026-06-01 21:29` | Crane's last lift. |
| 6 | `FK_TERMINAL_CALL` | int | `0` | FK → call. |
| 7 | `FK_TDR_REL` | int | `1` | FK → report version. |

**Note:** Crane counts per call range 2–9; per-crane window feeds `GROSS_HOURS_WORKED`.

---

## 5. `tdr_delay.csv` — 138 rows (one per delay)

| # | Column | Type | Example | Notes |
|---|--------|------|---------|-------|
| 1 | `ID_NUMBER` | int | `0` | Call carrying the delay. 59 distinct calls have delays. |
| 2 | `REL_NUM` | int | `1` | Report version. |
| 3 | `CL_CRANE_VESSEL` | str | `C` / `V` | **`C`**=crane-level; **`V`**=vessel-level. |
| 4 | `DELAY_CATEGORY` | str | `LOT` | Code from `tdr_delay_reason.csv`. 14 distinct. |
| 5 | `DELAY_REASON` | str | `Labour rest period` | Human-readable reason hint. |
| 6 | `DELAY_DURATION_HRS` | float | `0.29` | Delay hours. Range 0.13–3.77. |
| 7 | `CRANE_REL_NUM` | int | `4` | Which crane, when `CL_CRANE_VESSEL=C`. Blank for vessel-level. |
| 8 | `FK_TERMINAL_CALL` | int | `0` | FK → call. |
| 9 | `FK_TDR_REL` | int | `1` | FK → report version. |

**Attribution:** vessel-level delays (`V`) sum out of `GROSS_SHIFT_TIME`; crane-level (`C`) sum out of `GROSS_HOURS_WORKED`.

---

## 6. `tdr_delay_reason.csv` — 14 rows (code catalog)

| # | Column | Type | Example | Notes |
|---|--------|------|---------|-------|
| 1 | `ID` | int | `1` | Surrogate key. |
| 2 | `DRC_CODE` | str | `LOT` | Delay reason code. 14 distinct canonical codes. |
| 3 | `RESPONSIBILITY` | str | `T` / `V` / (blank) | **`T`**=terminal, **`V`**=vessel, blank=unrestricted. |
| 4 | `DRC_NAME` | str | `LABOUR - OTHER` | Full code name. |

**Reference:** every `DELAY_CATEGORY` in `tdr_delay.csv` must exist here, with a matching responsibility flag.

---

## Keying summary

- **Primary key:** `tdr_terminal_call.csv.ID_NUMBER` (0–109).
- **Foreign keys:** `FK_TERMINAL_CALL` / `ID_NUMBER` in header, move_summary, crane_deployment, delay all reference it.
- **`REL_NUMBER`/`FK_TDR_REL`/`REL_NUM`:** report version. All `1` in this release (column present because real TDR data is versioned).
- **Move reconciliation:** per call, operator rows + hatch-cover = crane rows = total moves.