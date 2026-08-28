# Track 1 — Ship Planning & Vessel Scheduling
## Field Briefing (read this first)

**The job in one line:** a shipping line must decide *which vessel, sailing which service, calls which port, at what time* — and keep that promise against a world that constantly breaks it.

**The problems someone in this field wrestles with every day:**

1. **Schedule reliability.** A published sailing date is a promise to shippers, feeder feeders, and terminal operators. Vessels miss it because of weather, port congestion, bunkering, or a late upstream call. Teams spend their lives chasing "schedule recovery" — how do you absorb a delay without cascading it through every port call in the voyage?

2. **Voyage construction.** Every sailing is a multi-leg loop with fixed port rotation. You must assign vessels (each with a max capacity and draft/canal limits) to services (strings of ports) so that capacity matches booked demand, transit time hits the service commitment, and no two vessels collide on the same berth-day at a shared port.

3. **Capacity and slot allocation.** Cargo is booked against a sailing (10-day rolling window, 30-day rolling window, LSDV — last sailable departure vessel). When bookings exceed capacity you either roll cargo ("rolled cargo," the freight world's dirty word) or break a schedule. Pricing, not data, often decides who gets the space.

4. **The living schedule.** Publish a working schedule (the "schedule of sailings"), then let later port changes, blank sailings (cancellations, often the most efficient move), and injection logic mutate it. You need *one* source of truth that line operations, commercial, and the terminal all agree on.

5. **The downstream contract.** Around the vessel call, you must coordinate revised ETA/ETD, berth windows, and the feeder window (the time a feeder/exchange vessel must arrive to transship) — because the next leg ship.

**A typical working day** = reconcile yesterday's actual port departures, apply the delay, decide whether to keep or blank the next sailing, alert the people who price and book against it, and update the terminal's slot model.

**What a good hack would do:** take the schedule + voyage + capacity data supplied, surface *where the risk is* (late-arriving vessels, oversold sailings, missed transshipment windows), and recommend the schedule edits that would recover it. The data is synthetic but the structure is real.

## Data files

| File | What it is |
|---|---|
| `vessels.csv` | Fleet — each vessel's capacity, draft, canal-tolerant flags |
| `sailings.csv` | Each scheduled voyage loop: service, port sequence, planned dates |
| `port_calls.csv` | Revised/observed arrival & departure at each call (the noisy reality) |
| `bookings.csv` | Cargo booked per vessel/sailing with rolling windows |
| `services.csv` | The published service strings (which ports each ship) |

## One real-world texture

Shanghai alone handles north of 40M TEU/yr (the world's busiest container port authority). A single delayed arrival on the Shanghai–Singapore leg doesn't just ripple — it collides with the whole region's berth calendar. That is the scale you're modeling.