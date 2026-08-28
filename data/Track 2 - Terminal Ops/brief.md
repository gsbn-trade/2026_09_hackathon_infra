# Track 2 — Terminal Operations & Transshipment
## Field Briefing (read this first)

**The job in one line:** a container terminal (Berth, yard, and gate) must move containers on and off vessels, store them, and hand them to the next leg — as fast, cheaply, and predictably as possible. The whole game is **productivity** (moves per hour) and **dwell** (how long a box sits before it leaves).

**The problems someone in this field wrestles with every day:**

1. **Berth productivity.** Quay cranes are the bottleneck asset — and the most expensive. A big boxship in Shanghai will want 4–6 cranes working it to hit 150–250 moves/hour. If cranes stand idle waiting for yard trucks or the wrong container stack, you lose thousands of dollars an hour. Primacy goes to **"moves per crane per hour"** and **vessel turnaround time**.

2. **The yard is the real constraint.** The container yard (stacked boxes) has finite slots and drives everything. If the yard is disorganised, a crane sits idle while trucks search stack-by-stack for the box it needs. **Yard utilisation, dwell time, stacking density, and rehandling** (moving a box that's on top to reach the one you want — every "rehandle" is pure waste) are the metrics that matter.

3. **Transshipment vs. local.** Transshipment = containers that arrive on one vessel and leave on another (import-then-export without leaving the terminal). Shanghai, Singapore, and Busan are hubs built on it — transshipment can be 30–50% of a hub's volume. The critical, unforgiving metric is the **cut-off / feeder window**: the transshipment box *must* get from the mother vessel discharge point to the feeder vessel's loading point within hours, or it "misses the connection" — a failed transshipment that costs revenue and reputation.

4. **Dwell time.** The time a box spends in the yard between discharge and pickup/dispatch. High dwell = congested yard = wrong slot = slow cranes. Low dwell sounds good but is a target only up to the point where you're charging demurrage/free-time. Balancing **free-time, demurrage charges, and yard capacity** against the gate flow is a constant optimisation.

5. **Operational flow & the handoff.** From vessel discharge → yard stacking → inter-crane transfer → gate-out (trucker) or feeder-load. Every handoff is a data event (EDI/OCR/terminal operating system/TOS). The historical barrier is **data silos**: the TOS knows berth moves, the gate system knows truckers, the port community system knows customs. Getting one coherent, schedulable picture across all of them is the fix everyone wants.

**A typical operating day** = decisions on berth allocation (which vessel at which berth, which cranes), yard placement (which stack, which zone, align by service and export cut-off), and real-time adherence: are we building the "export stack" so the vessel can load out of rotation without rehandling?

**What a good hack would do:** take the operational + throughput data supplied, surface the bottleneck (crane idle, yard congestion, connection misses), and recommend operational adjustments — berth swaps, crane allocation, yard zoning / dwell policy — that raise productivity or cut failed transshipments.

## Data files

| File | What it is |
|---|---|
| `port_throughput.csv` | Real annual TEU throughput — top container ports (Shanghai, Singapore, Ningbo, ...) |
| `berth_events.csv` | Vessel arrival/departure per berth, moves, cranes used, operational hours |
| `yard_moves.csv` | Container move records (discharge/load/rehandle) with positions and timing |
| `transshipment.csv` | Transshipment volumes & connections per service/vessel pair |
| `gate_dwell.csv` | Trucker gate-in/out + import dwell observed per container category |

## One real-world texture

Shanghai (Yangshan) runs the world's biggest automated terminal — fully remote cranes and transport vehicles. Yet even there, the binding constraint is yard space and the discipline of stacking so exports can be loaded without rehandles. Meanwhile Singapore's and Busan's hubs live or die by whether a transshipment box makes its feeder connection on time. Your dummy data captures that essential tension: berth productivity vs. yard dwell vs. connection timing.