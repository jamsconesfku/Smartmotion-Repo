# SmartMotion: Project Brief and Claude Code Kickoff

**Owner:** Sam Jones
**Prepared:** 7 November 2026
**Purpose:** This file hands the SmartMotion project over to a Claude Code session working in a new GitHub repository. It summarises everything decided and researched so far, and tells Claude Code how to set up the repo and build a **living dashboard** that tracks every task, contact, document and decision needed to take SmartMotion live as a business.

> Transcribed from the original PDF (`SMARTMOTION_PROJECT_BRIEF.pdf`). The live status of tasks, contacts and decisions is kept in `data/*.json`, not here. This file is the historical starting point.

---

## 1. What SmartMotion is

SmartMotion is a UK business built around a **6-DOF (six degrees of freedom) full-motion simulator** that Sam designed and built. The rig turns flight and driving game software into real movement. Riders see the action through a VR headset or screens and use force-feedback joysticks or steering wheels.

- **Website:** https://www.smartmotion.tech (product info: https://www.smartmotion.tech/product-information)
- **Public contact:** info@smartmotion.tech · 07968 615044
- **Currently presented as:** "A Skysmart MRO Ltd Company", based in Great Dunmow, Essex (about 5 minutes from Stansted Airport). Skysmart's own site links to it at https://www.skysmart.co.uk/flight-simulator.
- **Plan:** launch SmartMotion properly as a business in 2027.

### Two business lines

1. **Experiences (first priority, launching 2027).** Paid sessions on the rig at the Great Dunmow base, at corporate events and at airshows and other events. Gift vouchers go on sale first.
2. **Building and selling simulators (later).** SmartMotion intends to develop and sell its simulators, with options from complete systems (PC and VR installed) to kit packages. The website already says rigs are built "to suit your budget". Rig sales were explicitly **parked until the experiences business is running**. They stay on the roadmap but get no launch tasks yet.

A third area, **3D printing**, will be added. Sam will provide documents on what he does with 3D printing and how it fits (for example parts for rigs, cockpit controls, merchandise).

### History and track record (public sources)

- **MRO Europe 2024:** the simulator started as a "bit of fun" for Skysmart's stand and ran a "Top Gun" low-level-flying time trial (an F/A-18E Super Hornet through a valley). Aviation Week reported that it proved popular enough to become a new business line: https://mroevents.aviationweek.com/articles/exhibition-gimmick-spawns-new-business/
- **The idea came from** a local Scouts visit to Skysmart, where a gliding club set up a basic simulator. Sam then spent about five months adding the motion rig and VR.
- **2025:** Duxford Summer Airshow (Sally B fundraiser), Shuttleworth and Wycombe Air Park.
- **2026:** Duxford several times. A Skysmart STEM and Aviation Day was held at IWM Duxford in June 2026.
- **MRO Europe, Amsterdam, 27–29 Oct 2026:** a next-generation simulator was unveiled, with a Low Level Flight Challenge on the stand. Returning visitors came back to compete. The rig travelled by ferry (Harwich to Hook of Holland) under an ATA Carnet arranged through Maltacourt.
- **Story assets:** Skysmart owns a real ex-RAF **Scottish Aviation Bulldog** trainer. This is a strong marketing hook ("fly the Bulldog in VR").

---

## 2. The product (technical summary)

| Item | Detail |
|---|---|
| Platform | Single-seat 6-DOF motion platform: pitch, roll, yaw, surge, heave, sway |
| Actuators | 7 electric actuators: 6 for motion, plus 1 driving seat-belt tensioners that simulate g-force. No hydraulics. |
| Motion controller | Motion4Sim servo driver controller (upgraded to the newest generation in Oct 2026) |
| Motion software | FlyPT Mover (telemetry to motion; profiles per game) |
| Display | VR headset or screens, plus a spectator screen |
| Controls | Force-feedback joystick and throttle (flight) or steering wheel and pedals (driving); the rig converts between modes |
| Restraint | 5-point harness |
| Power | Single-phase electric; portable for events |

To confirm and record: rated rider load, footprint and exclusion zone, E-stop design, transport weight and size, PC specification, headset model. These values are needed for the ADIPS design review and the operations manual.

---

## 3. Business plan summary

Source: *SmartMotion 6DOF Simulator Experiences – Business Plan* (31 Oct 2026, 22 pages). Sam has the PDF; add it to `docs/source/`.

- **Three sales channels:** bookable sessions at the Dunmow base, corporate days (on-site or at the client) and walk-up sessions at airshows and events.
- **Target:** about **£13,000 a month** revenue within 12 months in the base case, and about £6,400 a month profit before owner pay. Break-even is about £3,900 a month (roughly 84 public sessions or 3 corporate days).
- **Selling point:** one rig does two jobs, full-motion flight in VR and rally or track driving. Rivals are mostly fixed-base flight sims or 2–3-axis racing rigs. Tagline: **"Fly it. Drive it. Feel it."**
- **Priority customers:** corporate team days and gift-voucher buyers first. Then aviation enthusiasts, student pilots and events.
- **Example prices:** £20 for a 10-minute taster, £39 for 20 minutes, £55–£65 for 30 minutes, £109 for a 60-minute Mission Hour and £159 for the flight-plus-car double. Corporate days (ex VAT) are £795 for a team challenge at the base, £1,250 for a half day on-site and £1,950 for a full day on-site.
- **Operations:** fixed flight days and car days (to avoid repeated conversions), 45-minute slots, and utilisation targets of 40%, rising to 60–70%.
- **Start-up costs:** about £9,600–£19,000, excluding software licences.
- **Launch:** full public opening **March 2027**. **Gift vouchers on sale from the end of November 2026** for the Christmas season.
- **Pricing check needed:** the nearest competitor, **VR Sim** in St Ives, Cambridgeshire (4-DOF rigs running DCS and Assetto Corsa), advertises "from £20 for 30 minutes mid-week". Recheck the plan's prices against theirs before vouchers go on sale.

---

## 4. Legal and compliance: what's needed before taking money

Before selling vouchers or tickets, SmartMotion needs:

1. **ADIPS inspection.** The Amusement Device Inspection Procedures Scheme is the UK industry scheme for rides that move members of the public (HSE guidance HSG175). As a new, self-built device the rig needs a **design review**, **assessment of conformity to design** and an **initial test**, after which it gets a **Declaration of Operational Compliance (DOC)**. It then needs an annual in-service inspection. Event organisers will ask for the DOC.
2. **Insurance.** Public and products liability of £5–10m, with paying riders on a moving 6-axis rig named in writing. Also employers' liability, equipment and goods-in-transit cover, and business interruption cover.
3. **Commercial software licences.** Consumer game licences do not allow paid public use (see Section 5).
4. **Booking, payments and vouchers.** An online system plus terms and conditions, a rider declaration and a UK GDPR privacy notice.
5. **Business admin.** Decide whether SmartMotion trades under Skysmart MRO Ltd or as its own company, confirm the VAT position, get landlord consent and check planning use at the Dunmow unit, and set up a separate bank account or cost centre.

**Key point:** by 30 Nov 2026 SmartMotion can legally sell **gift vouchers and dated tickets for 2027 sessions**, provided insurance, terms and licences are in place. **No paid rides until the ADIPS DOC is issued.**

---

## 5. Software licensing findings

| Software | Use | Commercial route | Cost / status |
|---|---|---|---|
| **X-Plane 12 Professional** | Flight | Buy direct from x-plane.com. A professional key is required whenever X-Plane is used to generate revenue. | $1,000 digital; $1,250 USB key (USB key works offline) |
| **DCS World** | Jets and warbirds | Eagle Dynamics offers a separate commercial site licence. Contact support@digitalcombatsimulator.com. VR Sim (St Ives) holds one, so there's a precedent. | By quote |
| **Assetto Corsa Commercial Pro** | Track and rally (rally via mods) | Sold only through authorised resellers such as Vesaro (Kent) and FPZERO. Choose the Pro tier because it allows third-party software like FlyPT Mover. | About £3,750 per simulator, one-off |
| **rFactor 2** | Circuit racing | Commercial licence via info@motorsportgames.com | By quote |
| **FlightGear** | Flight (open source, GPL) | Free; paid use is allowed | Free; candidate base for a custom SmartMotion sim |
| **FlyPT Mover** | Motion control | Confirm commercial use with the developer (XSimulator forum) | To confirm |
| **Microsoft Flight Simulator 2024** | n/a | **No commercial licence available.** Do not use for paid sessions. | Not usable |
| **Prepar3D** | n/a | Licensed for training, explicitly not for entertainment | Not suitable |
| Automobilista 2, EA WRC, DiRT Rally | n/a | No commercial licence found | Not usable |

Third-party aircraft, scenery and mods each need separate written permission. **Advertise experiences by type** ("Fast Jet Low-Level", "WW2 Fighter Sortie", "Rally Stage") rather than by game or brand name.

**Custom simulator idea (parked):** build a SmartMotion-owned flight experience on FlightGear, adding a UDP telemetry bridge into FlyPT Mover, one-click experience presets and an operator panel. A later option is a Unity or Unreal sim using the JSBSim flight model and OpenXR. A four-phase plan was outlined: prove VR and motion work → aircraft and scenery → experience presets → trial runs and paperwork.

---

## 6. Contacts directory

### ADIPS inspection bodies (registered for design review, conformity and initial test)

| Company | Contact | Email | Phone | Address | Notes |
|---|---|---|---|---|---|
| John H Rundle Ltd | Ken Rundle | clare@rundles.co.uk | 01205 480431 | Main Road, New Bolingbroke, Boston, Lincs PE22 7LN | Nearest full-scope body. **Send first.** |
| TÜV SÜD | Patrycjusz Idzikowski | patrycjusz.idzikowski@tuvsud.com | 03300 169924 | Room 103, County Way, Barnsley S70 2AG | Large international firm; credibility with insurers. **Send first.** |
| Westlakes Engineering Ltd | Ron Dale | attraction-safety@westlakes.co.uk | 0161 236 8203 | Unit 2.1, 20 Dale Street, Manchester M1 1EZ | **Send first.** |
| Leisure Technical Consultants | Bob Nicholls | ltci@ltci.co.uk | 0161 351 9526 | 73 Crescent Road, Dukinfield SK16 4EU | Backup; also offers consultancy |
| Capstone Inspections | Paul Capper | paul@capstone-inspections.com | 07736 641420 | 19 South Road, Dorset BH19 2QR | Backup |
| R. J. Associates | Craig Kirkman | craig@rj-a.com | 07850 445934 | Cheshire | Backup |
| Comply: Amusement Safety | Grace Narca | comply@complysafe.co.uk | 07841 658643 | Worcestershire | Backup |
| Kraken NDT (Essex) | Jay Wilson | hireamusement@gmail.com | 07450 447958 | Chestnut Farm, South Road, South Ockendon RM15 6DT | **Testing only** (non-destructive weld/crack testing); local |
| ADIPS Ltd | n/a | office@adips.co.uk | n/a | n/a | Scheme office; register at adips.co.uk |

Source: https://adips.co.uk/find-a-registered-inspection-body/. The register contains some errors, so verify each email on the company's own website.

### Insurance brokers

| Broker | Email | Phone | Address / notes |
|---|---|---|---|
| Broker2U (Deborah) | deborah@broker2u.co.uk | 01245 226318 | Chelmsford area; fairground and funfair specialist. **Send first.** |
| Acer Insurance Services | info@acerinsurance.co.uk | 01959 546823 | Winterton House, High Street, Westerham, Kent TN16 1AQ; showmen specialist. **Send first.** |
| Peacock Insurance Services | info@peacockinsurance.co.uk | 02476 437 600 | 1410 Spring Place, Herald Avenue, Coventry CV5 6UB; amusement park cover. **Send first.** |
| Skysmart's existing broker | n/a | n/a | May be able to extend the current policy. **Send first.** |
| Livingstones Insurance | web form | 020 8903 9412 | Fairground operators' cover, public liability up to £10m. Backup. |
| Arthur J Gallagher | ajg.com/uk | n/a | Theme parks and leisure attraction team. Backup. |

### Software vendors

- Eagle Dynamics (DCS): support@digitalcombatsimulator.com. Registered address: Route de la Glâne 107, 1752 Villars-sur-Glâne, Switzerland.
- Laminar Research (X-Plane): x-plane.com
- Assetto Corsa resellers: Vesaro (Kent), FPZERO (fpzero.co.uk)
- Motorsport Games (rFactor 2): info@motorsportgames.com

### Market

- **VR Sim**, St Ives, Cambridgeshire (vr-sim.co.uk): nearest competitor. Runs 2 × 4-DOF DCS rigs and an Assetto Corsa rig. Prices from £20 for 30 minutes mid-week.
- Other local simulator experiences: VA Airline Training at Cambridge Airport (A320/737 simulators; £360 for 1 hour).

---

## 7. Master task list (status as of 7 Nov 2026)

Target: **legal and ready for voucher sales by 30 Nov 2026**, with the **first paying riders in March 2027**.
Status key: `done` · `in_progress` · `todo` · `waiting` · `parked`

The full list now lives in `data/tasks.json`. Original groupings:

- **Already done (D-01 – D-09):** business plan, licensing research, ADIPS research, insurance research, launch checklist, ADIPS email draft, insurance email draft, operations manual draft v0.1, emails pack PDF.
- **Week 1 (3–9 Nov, W1-01 – W1-07):** business set-up and long-lead requests.
- **Week 2 (10–16 Nov, W2-01 – W2-07):** insurance and safety paperwork.
- **Week 3 (17–23 Nov, W3-01 – W3-05):** licences and booking system.
- **Week 4 (24–30 Nov, W4-01 – W4-08):** terms, website and go-live.
- **Before the first paying rider (Dec 2026 – Mar 2027, P-01 – P-09).**
- **Parked / future (F-01 – F-05).**

---

## 8. Documents created so far

| Document | Format | Where |
|---|---|---|
| SmartMotion business plan | PDF (Sam has it) | Add to `docs/source/` |
| SmartMotion Launch Checklist | Claude Doc + PDF | https://claude.ai/artifact/SQ2MhWDLs1xKCTqy4zS7Do · `SmartMotion_Launch_Checklist.pdf` |
| SmartMotion Operations Manual (draft v0.1) | Claude Doc + PDF | https://claude.ai/artifact/4DUSRs4hFLLmB64XDfLdwz · `SmartMotion_Operations_Manual.pdf` |
| Inspection and Insurance Emails pack | PDF | `SmartMotion_Inspection_and_Insurance_Emails.pdf` |

Sam should copy these PDFs into `docs/source/` in the repo.

---

## 9. Open questions and decisions

- Trading entity: a Skysmart MRO Ltd division, or a new SmartMotion Ltd?
- VAT treatment of public prices.
- Final rider limits and rig data for the manual (load, height, age, exclusion zone, E-stop behaviour).
- Which simulation titles to license first (recommended: X-Plane Pro now; ask Eagle Dynamics about DCS; Assetto Corsa Commercial Pro for driving).
- Final prices after the VR Sim comparison.
- Booking system choice.
- When to reopen the simulator sales line.
- How 3D printing fits into the business.

---

## 10. Working principles agreed

- Experiences first; simulator sales later.
- Nothing paid runs on the rig until ADIPS sign-off and insurance are in place.
- Never charge for sessions on consumer-licensed software.
- Advertise experiences by type, not by trademarked aircraft or game names.
- Keep written records of everything: inspections, checks, training, incidents, licences.

---

## 11. Sources

- SmartMotion website: https://www.smartmotion.tech · https://www.smartmotion.tech/product-information
- Aviation Week, "Exhibition 'Gimmick' Spawns New Business": https://mroevents.aviationweek.com/articles/exhibition-gimmick-spawns-new-business/
- Aviation Week MRO Europe 2024 gallery: https://aviationweek.com/shows-events/mro-europe/gallery-products-services-display-mro-europe-2024
- Air League, Skysmart STEM and Aviation Day (June 2026): https://airleague.co.uk/news/skysmart-stem-and-aviation-day-ignites-scouts-curiosity-in-aviation-pathways
- ADIPS register: https://adips.co.uk/find-a-registered-inspection-body/
- X-Plane licensing: https://x-plane.helpscoutdocs.com/article/25-what-license-do-i-need
- DCS licence: https://www.digitalcombatsimulator.com/en/support/license/
- Assetto Corsa commercial licensing: https://simpullsports.com/guides/assetto-corsa-commercial-license
- DCS forum (VR Sim licence precedent): https://forum.dcs.world/topic/269985-dcs-motion-simulator/

---

## 12. Instructions for Claude Code (summary)

- **Goal:** make this repo SmartMotion's single source of truth: Markdown knowledge base + a browser dashboard showing every task, status, due date, go-live gates, contacts, licences, documents and open decisions.
- **Data:** `data/tasks.json`, `contacts.json`, `licences.json`, `documents.json`, `decisions.json`, `milestones.json` (plus `changelog.json`). Every record has an `id`, `status` and `updated` date.
- Task `status`: `todo`, `in_progress`, `waiting`, `done`, `parked`. Task `area`: Admin, Finance, Legal, Insurance, Safety, Software, Engineering, Operations, Sales, Website, Marketing, Events, Launch, 3D Printing, Product Sales.
- **Dashboard:** single self-contained `dashboard/index.html`, no build step, served via GitHub Pages; header countdowns to 30 Nov 2026 and March 2027 plus % done; go-live gates; task board filterable by status/area/owner with overdue and "waiting on" shown; contacts (click-to-email/call), licences, documents, open decisions, recent changes; mobile-friendly.
- **Ongoing:** when Sam reports progress, update `tasks.json` and the change log and commit. When Sam uploads a document, file it in `docs/source/`, summarise into the right topic doc, add new tasks/contacts/decisions. Keep everything factual, mark assumptions, and never mark a compliance item done without Sam's confirmation.
