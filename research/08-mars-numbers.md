# 08 - Mars numbers for the Jezero base demo

Research date: 2026-10-23. Every value carries a URL, the source's date and a quote or table reference.
Anything I could not source is marked **UNSOURCED**. "Secondary" means a news or web page and not the mission's own document.
Some web quotes were returned by a fetch tool that summarises pages. Quotes are as returned and are short fragments. Re-open the URL if one will be shown on screen verbatim.

## TL;DR table

| Quantity | Value | Unit | Source URL | Source date | Quote / table ref |
|---|---|---|---|---|---|
| Opp. energy, sol 5105, tau ~1.0 | 468 | Wh/sol | https://www.marsdaily.com/reports/Regional_dust_storm_is_affecting_Opportunity_Mars_rover_999.html (JPL MER update republished) | 2018-06-12/13 | "468 watt-hours of energy", tau "around 1.0" |
| Opp. energy, sol 5106, tau 2.1 | 345 | Wh/sol | same | 2018-06-12/13 | "345 watt-hours with a tau of 2.1" |
| Opp. energy, sol 5107, tau >3.0 (not measured) | 133 | Wh/sol | same | 2018-06-12/13 | "133 watt-hours"; tau "above 3.0" (estimated) |
| Opp. energy, sol 5111 (2018-06-10), tau 10.5 | 21 | Wh/sol | https://science.nasa.gov/resource/on-mars-light-is-energy/ | graphic 2018-06-13; page updated 2024-11-07 | tau "10.5", energy "21 watt-hours", lowest then recorded |
| Opp. final report, tau 10.8 | 22 | Wh | https://www.planetary.org/articles/06-mer-update-opportunity-dust-storm-sleep | 2018-06-14/15 | "estimated at 10.8, 'a record high for measurements on Mars'"; "just 22 watt-hours" |
| Brief's pair tau 0.6 -> 645 Wh and tau 1.5 -> 345 Wh | secondary and **conflicts with JPL** | Wh | https://www.wral.com/story/17627296/ | 2018-06-14 | "tau of 0.6 ... 645 watt hours"; "tau was 1.5 with 345 watts hours" |
| Opp. pre-storm energy (end of May 2018) | ~650 | Wh/sol | https://www.planetary.org/articles/08-mer-update-opportunity-sleeps | 2018-08-01 | "upwards of 650 watt-hours" |
| Opp. energy at landing, clean arrays | 950+ | Wh/sol | same | 2018-08-01 | "950+ watt-hours" |
| Opp. 2007 storm, sol 1225, tau 4.12 | 280 | Wh/sol | https://www.marsdaily.com/reports/Opportunity_Waiting_For_Dust_To_Settle_999.html | 2007-07-17 | tau "4.12" at "sol 1225", "a mere 280 watt-hours of array energy" |
| Opp. 2007 storm minimum | 128 | Wh/sol | https://www.jpl.nasa.gov/news/nasa-mars-rovers-braving-severe-dust-storms | 2007-07-20 (update 07-23) | "dropped even lower, to 128 watt hours" |
| Opp. 2007 normal output | ~700 | Wh/sol | same | 2007-07-20 | "roughly 700 watt hours daily" (paraphrase by fetch tool) |
| 2007 peak tau, previous rover record | 5 to 5.5 | tau | https://www.planetary.org/articles/06-mer-update-opportunity-dust-storm-sleep | 2018-06-14 | "of 5 to 5.5, during the planet-encircling dust event Opportunity survived in 2007" |
| MER array area | 1.3 | m2 | **UNSOURCED** (secondary: energymatters.com.au/renewable-news/em570/, not page-verified) | n/a | only a search-result summary; not confirmed on a NASA page |
| Mars sol length | 24h 39m 35.244s = 88775.244 | s | https://www.giss.nasa.gov/tools/mars24/help/algorithm.html | page updated 2025-01-07 | C-2 divisor 1.0274912517 d; 1.0274912517 x 86400 = 88775.244 s (my arithmetic) |
| Mars solar day (hours) | 24.6597 | h | https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html | updated 2025-05-19 | "Length of day: 24.6597" |
| Synodic period | 779.94 | d | same | 2025-05-19 | "779.94" |
| Earth-Mars distance min / max | 54.6 / 401.4 | 10^6 km | same | 2025-05-19 | "54.6" and "401.4" |
| One-way light time min / max | 3.04 / 22.3 | min | computed from the row above | n/a | my calculation, d/c |
| Jezero crater centre | 18.38 N, 77.58 E, diameter 45 km | deg, km | https://en.wikipedia.org/wiki/Jezero_(crater) | accessed 2026-10-23 | "18.38°N 77.58°E", "45 km (28 mi)". Secondary. Planetocentric vs planetographic is **not stated** |
| Octavia E. Butler Landing | 18.44 N, 77.45 E | deg | https://en.wikipedia.org/wiki/Octavia_E._Butler_Landing | accessed 2026-10-23 | "18°26′N 77°27′E / 18.44°N 77.45°E". Secondary. Landed 2021-02-18, named 2021-03-05 |
| Octavia E. Butler Landing, finer | 18.445 N, 77.451 E | deg | https://christopher-riley.medium.com/from-mars-to-earth-18ae2597e3fe | n/a | secondary blog; 4-decimal values 18.4446 / 77.4509 are **UNSOURCED** |
| Mars to Earth distance, 2026-10-23 | 1.50407 | AU | JPL Horizons API (query below) | 2026-10-23 | delta = 1.50406590604046 AU, deldot -13.48 km/s |
| One-way light time, 2026-10-23 | 12.51 | min | computed from the Horizons delta | 2026-10-23 | delta x 499.0048 s/AU |
| Round trip, 2026-10-23 | 25.0 | min | same | 2026-10-23 | 2 x 12.51 |
| Closest approach (opposition) | 0.678 AU, 5.64 min one-way | AU, min | Horizons | 2027-02-20 | delta = 0.67791881744057 AU |
| Next launch window (Earth to Mars) | 2028-12-10 to 2029-01-17 | date | https://www.forbes.com/sites/kevinholdenplatt/2026/09/29/rocket-lab-protest-could-torpedo-nasas-2028-launch-of-mars-orbiter/ | 2026-09-29 | NASA handbook dates, **second-hand**. I could not open the page (HTTP 403) |
| Current window | opens Nov 2026, closes about a month later | n/a | https://www.19fortyfive.com/2026/08/the-mars-launch-window-opens-in-november-2026-and-closes-about-a-month-later-the-next-one-is-in-2029/ | 2026-08-09 | "The next window opens in November 2026 and closes roughly a month later." Secondary |
| MMX launch (use for the "window is live" claim) | 2026-10-20, reserve to 2026-11-07 | date | https://global.jaxa.jp/press/2026/08/20260820-1_e.html | 2026-08-20 | "October 20, 2026", reserve "October 21, 2026 - November 7, 2026". I did not confirm it launched |
| Falcon Heavy price | 97 (reusable, 2022) / 150 (expendable, 2017) | US$ M | https://en.wikipedia.org/wiki/Falcon_Heavy | accessed 2026-10-23 | "US$97 million (2022)", "US$150 million (2017)". Secondary. The SpaceX PDF returned 404, so this is not first-party |
| Falcon Heavy payload | LEO 63.8 t expendable, GTO 26.7 t, Mars 16.8 t | t | same | accessed 2026-10-23 | table "Since Apr 2017" column. Expendable |
| Falcon 9 payload to Mars | 4 | t | same | accessed 2026-10-23 | Falcon 9 column |
| Crew oxygen | 0.816 | kg/crew-day | https://ntrs.nasa.gov/citations/20180001338 (BVAD Rev1, PDF p.77, printed p.63) | Jan 2018 | Table 3-33 "Oxygen Consumed kg/CM-d 0.816" |
| Crew food (dry, as shipped) | 1.51 | kg/crew-day | same | Jan 2018 | Table 3-33 "Food Consumed; Mass (without packaging) 1.51"; energy 12.59 MJ/CM-d |
| Crew potable water | 2.5 | kg/crew-day | same | Jan 2018 | Table 3-33 "Potable Water Consumed 2.5" (includes about 0.5 food rehydration) |
| Crew CO2 produced | 1.04 | kg/crew-day | same | Jan 2018 | Table 3-33 "Carbon Dioxide Load 1.04" |
| Total water, early planetary base | 4.48 | kg/crew-day | same (PDF p.91) | Jan 2018 | Table 4-20 "Total Water Consumption ... Early Planetary Base 4.48" |
| Total water, mature planetary base | 9.82 | kg/crew-day | same | Jan 2018 | Table 4-20 "Mature Planetary Base 9.82" |
| Mars surface crew water (NASA JSC study) | 13.3 with laundry / 6.0 without | kg/person-day | https://ntrs.nasa.gov/api/citations/20170002074/downloads/20170002074.pdf (Hoffman et al.) | 2017-03-04 | "Mars Surface Crew (with laundry): ~3.5 gallons/person/day (13.3 kg/person/day)" |
| Li-ion cell specific energy | 100 to 150 (cell level) | Wh/kg | BVAD Rev1, Table 3-15 (PDF p.52) | Jan 2018 | "Lithium-ion with Liquid Electrolyte 200 to 300 [Wh/L] 100 to 150 [Wh/kg] ... 1,500 cycles, 60% DoD, TRL 5 to 9" |
| Habitat plus base nominal load | ~20 | kWe | https://ntrs.nasa.gov/api/citations/20120012929/downloads/20120012929.pdf (Cataldo, DRA 5.0 power) | 2009-06 | "Nominal total load power for the crew phase is approximately 20 kWe, for both day and night operation." Habitat scaled from a 4-crew lunar habitat |
| Same, consumables-only ISRU, daytime average | ~12 | kWe | same | 2009-06 | "total average day power is reduced to ~ 12 kWe" |
| Ascent-O2 ISRU plant | 66 (8 h/day), 22 continuous | kWe | same | 2009-06 | "66 kWe operating nominally for 8 hours a day (22 kWe continuous)" |
| Early Mars base loads, Jezero, with ISRU | 34.2 day / 35 night | kW | https://ntrs.nasa.gov/api/citations/20160011275/downloads/20160011275.pdf (Rucker, AIAA Space 2016, slide 16) | 2016-09 | "requires 34.2 kW during the day and 35 kW at night" (first two landers, around-the-clock propellant production) |
| Same, dust storm | 10.985 day / 11.728 night | kW | same | 2016-09 | "power would be reduced to 10,985 W during the day and 11,728 W at night" |
| Four landers with crew, nominal | 31.915 day / 26.790 night | kW | same | 2016-09 | "31,915 W during nominal daytime operation and 26,790 W at night" |
| Four landers with crew, dust storm | 22.945 day / 24.060 night | kW | same | 2016-09 | "22,945 W during the day, and 24,060 W at night during a dust storm" |
| ISRU water production rate (design basis) | 1.5 | kg/hr water | https://ntrs.nasa.gov/api/citations/20180005542 (Kleinhenz et al.) | 2018 | slide 5: "1.5 kg/hr water -> 0.67 kg/hr CH4 and 2.68 kg/hr O2" |
| Water needed per 4-crew 500-day mission | 20 (ascent propellant) + 25 (life support) + 23 (rover reactants) | t | Hoffman et al. 20170002074, slide 5 | 2017-03-04 | "16 tons/year of water extraction provides on-going exploration crew support" |
| Rodwell melt energy | **UNSOURCED as a number** (the source has only a graph "Energy Required to Melt 1000 kg of Ice") | kWh/kg | same, slide 23 | 2017-03-04 | my physics: (2.0 kJ/kg-K x 50 K + 334 kJ/kg) / 3600 = 0.12 kWh/kg at -50 C ice |
| MOXIE total / peak | 122 g total; 12 g/hr peak; 300 W | g, g/hr, W | https://en.wikipedia.com/wiki/MOXIE (search summary) and press coverage | 2023-09 | the 300 W figure is the Wikipedia infobox only. Secondary |

## 1. Solar power vs dust opacity

### What the primary record says (and where the brief is wrong)

The JPL mission update of 2018-06-12 gives these pairs:

| sol | date | tau | Wh/sol |
|---|---|---|---|
| 5105 | 2018-06-03 | ~1.0 | 468 |
| 5106 | 2018-06-04 | 2.1 | 345 |
| 5107 | 2018-06-05 or 06 (the text is inconsistent) | >3.0, estimated | 133 |
| 5111 | 2018-06-10 | 10.5 (JPL graphic) or 10.8 (later press and Planetary Society) | 21 (graphic) or 22 (press) |

- The brief's pair **tau 0.6 -> 645 Wh** and **tau 1.5 -> 345 Wh** comes from WRAL, a secondary source. It conflicts with JPL on the tau for the 345 Wh sol (1.5 vs 2.1) and on the dates.
- Spaceflight Now says 645 Wh was seen when the storm was first detected (May 30). I did not read this as a tau pair.
- The Planetary Society (2018-08-01) puts pre-storm output at "upwards of 650 watt-hours". That fits 645 Wh as a pre-storm value, but I found no primary source that attaches tau 0.6 to it.
- **Recommendation:** show JPL's pairs (1.0, 468), (2.1, 345), (10.5, 21). Show 645 Wh as "pre-storm, ~650 Wh". Do not show "tau 1.5 -> 345".
- The date of the 22 Wh report varies by source. Planetary Society says June 10 or 11. Astronomy Now says June 6. The JPL graphic puts it at sol 5111 = June 10.

### 2007 storm

- Sol 1225 (reported 2007-07-17): tau 4.12 -> 280 Wh/sol.
- The same report: at tau 5.0 output would be "roughly 150 watt-hours".
- Minimum of 128 Wh/sol came a few sols later, with no tau in the JPL release.
- Late August 2007, from the search summary only (not page-verified): tau about 3.7 gave 230-240 Wh.
- The 2007 normal output was about 700 Wh, so the 2007 arrays were much cleaner than the 2018 ones. The 2018 pre-storm output was about 650 Wh, versus 950+ Wh at landing.
- **Dust factor:** I found no source that states a numeric dust factor for sols 1225 or 5105-5111. The one value I saw is from a search summary, not a page I read: sol 2961, 395 Wh, tau 0.387, dust factor 0.559. Treat it as **UNSOURCED** until checked.
- Because the arrays differ in cleanliness, 2007 and 2018 points must not be fitted as one curve without normalising. The 2007 point sits well above the 2018 curve: at tau 4.12 the 2018 fit gives ~180 Wh, against 280 Wh observed.

### Array area for scaling

- MER arrays are about 1.3 m2. I could not confirm this on a NASA page. The NTRS record 20050186821 (Turgay 2004) does not state it. **UNSOURCED, secondary only.**
- If you accept 1.3 m2 and 2018 conditions, E0 about 650 Wh/sol is about 500 Wh/sol/m2 (my arithmetic). Because the 2018 arrays were dusty, E0 for a clean array should be higher. At landing, 950+ Wh/1.3 m2 is about 730 Wh/sol/m2.
- A real base array would be a different cell technology. Treat the per-m2 number as order-of-magnitude.

### Fit

Least-squares fits (my calculation, scipy, run 2026-10-23):

| data set | model | E0 (Wh/sol) | k (per tau) | diffuse term | predictions |
|---|---|---|---|---|---|
| JPL: (1.0,468), (2.1,345), (10.5,21) | E0 * exp(-k tau), log-linear | 668 | 0.329 | n/a | 481, 335, 21 |
| same | E0 * (exp(-k tau) + d), nonlinear | 634 | 0.297 | 0.000 | 471, 340, 28 |
| JPL with (10.8, 22) | log-linear | 653 | 0.314 | n/a | 477, 338, 22 |
| JPL plus (0.6, 645) | log-linear | 714 | 0.336 | n/a | 584, 510, 352, 21 (poor: 645 is not consistent) |

- **Use:** `E(tau) = 650 * exp(-0.31 * tau)` Wh/sol for the Opportunity array in 2018 condition.
- The fitted diffuse fraction is about 0. Within the verified points there is no sign of a diffuse-light floor, and tau 10.5 still gives 21 Wh.
- Point-to-point slopes are 0.28 (tau 1.0 to 2.1) and 0.33 (tau 2.1 to 10.5). The curve is close to single-exponential.
- The sol 5107 point (133 Wh at tau >3) is only a bound: 650 * exp(-0.31 * 3) is about 256 Wh, so 133 Wh implies tau of about 5 or rapid dust deposition. Do not plot it as a tau pair.
- For a base array scale linearly: `E_base = E(tau) * (A_base / 1.3)`, then multiply by a cell-efficiency ratio you choose and label as assumed.
- The 2007 normalised slope is `ln(700/280)/4.12 = 0.22`, if you take tau ~0 for the 700 Wh baseline (assumption). So k lies in a range of about 0.22-0.33 depending on array cleanliness and the diffuse share. I found no peer-reviewed tau-to-energy relation. I did not find the Lemmon papers.

## 2. Mars time

Source: https://www.giss.nasa.gov/tools/mars24/help/algorithm.html, "Updated 2025-01-07" (Allison and McEwen 2000, Allison 1997).

- A-2: JD_UT = 2440587.5 + millis / 8.64e7
- A-4: TT-UTC = (TAI-UTC) + 32.184 s. The page's leap-second table ends at the end of 2016 (TAI-UTC = 37 s). Use 37 s from then on.
- A-5: JD_TT = JD_UT + (TT-UTC) / 86400
- A-6: dtJ2000 = JD_TT - 2451545.0
- B-1: M = 19.3871 + 0.52402073 dtJ2000 (deg)
- B-2: alpha_FMS = 270.3871 + 0.524038496 dtJ2000 (deg)
- B-3: PBS = sum over i = 1..7 of A_i cos[(0.985626 dtJ2000 / tau_i) + phi_i], using the constants table in the code below.
- B-4: (nu - M) = (10.691 + 3.0e-7 dtJ2000) sin M + 0.623 sin 2M + 0.050 sin 3M + 0.005 sin 4M + 0.0005 sin 5M + PBS
- B-5: Ls = alpha_FMS + (nu - M)
- C-1: EOT = 2.861 sin 2Ls - 0.071 sin 4Ls + 0.002 sin 6Ls - (nu - M) (deg; /15 for hours)
- C-2: MST = mod24{24 h x [(JD_TT - 2451549.5)/1.0274912517 + 44796.0 - 0.0009626]}
- C-3: LMST = mod24{MST - Lambda/15}, with Lambda in degrees **west**
- C-4: LTST = LMST + EOT/15
- Sol length: 1.0274912517 d = 88775.244 s = 24h 39m 35.244s.

**Code check.** I ran the JS below for 2026-10-23 12:00 UTC at 77.58 E. It gave MSD 54321, MTC 15:04:50.7, LMST 20:15:09.9, LTST 19:41:02.9, Ls 11.36. I did not check it against the page's two worked examples, because I did not capture their expected values. Ls = 11.36 is plausible for the start of a Mars year in late 2026. Verify against the page's examples before you rely on it.

**Coordinates**
- Jezero crater centre: 18.38 N, 77.58 E (Wikipedia, secondary). The reference frame is not stated. For a sunclock a 0.1 degree difference is under 1 minute of local time.
- Octavia E. Butler Landing: 18.44 N, 77.45 E (Wikipedia, citing NASA GISS "Mars Lander Missions"). The 4-decimal values in the brief are **UNSOURCED**.
- USGS Gazetteer: the only entry I reached was Jezero Mons (a different feature). I did not retrieve the crater's own record.

## 3. Earth-Mars distance and light time

**Source:** JPL Horizons API, queried 2026-10-23 (DE441, Mars geocentric, apparent range). Query:

```
https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='499'&OBJ_DATA='NO'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&START_TIME='2026-10-23'&STOP_TIME='2027-06-01'&STEP_SIZE='30d'&QUANTITIES='20'
```

| date (UT) | delta (AU) | deldot (km/s) | one-way light time (min) | round trip (min) |
|---|---|---|---|---|
| 2026-10-23 | 1.50407 | -13.481 | 12.51 | 25.0 |
| 2026-11-22 | 1.25576 | -14.966 | 10.44 | 20.9 |
| 2026-12-22 | 0.99576 | -14.577 | 8.28 | 16.6 |
| 2027-01-21 | 0.77316 | -10.187 | 6.43 | 12.9 |
| 2027-02-20 | 0.67792 | -0.002 | 5.64 | 11.3 |
| 2027-03-22 | 0.77157 | +9.962 | 6.42 | 12.8 |
| 2027-04-21 | 0.98792 | +14.122 | 8.22 | 16.4 |
| 2027-05-21 | 1.24007 | +14.558 | 10.31 | 20.6 |

- Light times are my arithmetic: `delta_AU x 499.004784 s`. Horizons header states 1 au = 149597870.700 km and c = 299792.458 km/s.
- Range: 3.04 min (54.6e6 km) to 22.3 min (401.4e6 km), from the NSSDC fact sheet distances.
- **The brief's "40-minute round trip" is not realistic now.** Today the round trip is about 25 minutes. It falls to about 11 minutes at the 2027-02-20 opposition. Full-range round trip is 6 to 45 minutes (2 x 3.04 to 2 x 22.3). 40+ minutes happens only near solar conjunction.
- **Honest number to show:** compute it live from a date. For the demo default (late 2026), show "about 25 min round trip (12.5 min one-way)", counting down toward about 11 min in Feb 2027. Mention that conjunction can add solar-blackout periods. I did not source blackout duration.

**Offline options**
1. `astronomy-engine` (npm). License: **MIT**, "Copyright (c) 2019-2025 Don Cross" (https://raw.githubusercontent.com/cosinekitty/astronomy/master/LICENSE, fetched 2026-10-23). API from memory, **not verified here**: `Astronomy.GeoVector(Astronomy.Body.Mars, date, true).Length()` returns AU. Check the docs before use.
2. Precompute a Horizons table (daily over the demo span) and embed it. This needs no library and is exact. The API call above works with `STEP_SIZE='1d'`.
3. Keplerian approximation: use the NSSDC elements (a = 1.52366231 AU, e = 0.09341233 for Mars). I did not write or test this. Expect errors of a few percent in distance, so use it only as a fallback.

## 4. Launch windows

- Synodic period: 779.94 d (NSSDC fact sheet, updated 2025-05-19).
- **Current window:** opens November 2026 and closes about a month later (19FortyFive, 2026-08-09, secondary). JAXA's MMX is scheduled for 2026-10-20 with a reserve period to 2026-11-07 (JAXA press release 2026-08-20). I did not confirm that it launched.
- **Next window:** 2028-12-10 to 2029-01-17, per Forbes (2026-09-29), which attributes it to NASA's "Interplanetary Mission Design Handbook". I could not open the page (403) and found no primary copy. A simplified Hohmann calculator (crunchify.net/tools/launch-windows) gives 2028-12-22 to 2029-01-21, which is a weaker source. Treat dates as "about Dec 2028 to Jan 2029".
- Window after that: 2031-01-28 per the same Forbes article (second-hand).
- A crewed Starship Mars launch is not scheduled in either window. I found only the 19FortyFive and secondary statements that SpaceX's timeline slipped, so say nothing stronger on screen.

## 5. Launch cost per kg

First-party SpaceX source: not retrieved (the Capabilities and Services PDF returned 404 on both URL spellings tried). Figures are from Wikipedia's Falcon Heavy page, which cites SpaceX's sheet ("US$97 million (2022)", "US$150 million (2017)").

| basis | calculation (mine) | US$/kg |
|---|---|---|
| FH reusable list price / Mars payload 16.8 t | 97e6 / 16,800 | ~5,800 (but 16.8 t is the **expendable** figure, so this is optimistic) |
| FH expendable price / Mars payload 16.8 t | 150e6 / 16,800 | ~8,900 |
| FH reusable price / LEO 63.8 t (expendable payload) | 97e6 / 63,800 | ~1,520 (modaltrans.com gives about the same) |

**Uncertainty**
- The payload to Mars is a theoretical maximum on an expendable vehicle. The $97M price is for a reusable flight, which carries far less. The two do not match, so the cost per kg is a floor.
- Landed mass on Mars is a small fraction of the trans-Mars injection mass (entry, descent and landing hardware, propellant). I have no sourced landed-mass fraction (**UNSOURCED**).
- NASA and government launches cost more than list price (spacenexus.us: "$100M-$300M+", secondary).
- **Suggested demo figure:** about $1,500/kg to LEO (list price basis) and about $6,000-9,000/kg of trans-Mars injected mass. Label them "list-price floor, not landed cost".

## 6. Crew consumption

All from NASA/TP-2015-218570/REV1, "Life Support Baseline Values and Assumptions Document", Anderson, Ewert, Keener, January 2018, https://ntrs.nasa.gov/citations/20180001338. I read the downloaded PDF text. PDF page numbers are given.

Table 3-33 "Summary of Nominal Human Metabolic Interface Values" (PDF p.77), for an 82 kg crew member:

| item | value | unit |
|---|---|---|
| Oxygen consumed | 0.816 | kg/CM-d |
| Carbon dioxide load | 1.04 | kg/CM-d |
| Food consumed, mass without packaging | 1.51 | kg/CM-d |
| Food energy content | 12.59 | MJ/CM-d |
| Potable water consumed | 2.5 | kg/CM-d |
| Metabolic water | 0.4 | kg/CM-d |
| Total metabolic heat load | 12.00 | MJ/CM-d |

Table 4-20 "Typical Steady-State Water Usage Rates for Various Missions" (PDF p.91), kg/CM-d:

| item | Early Planetary Base | Mature Planetary Base |
|---|---|---|
| Drinking | 2.00 | 2.00 |
| Food rehydration | 0.50 | 0.50 |
| Urinal flush | 0.50 | 0.50 |
| Personal hygiene | 0.4 | 0.4 |
| Shower | 1.08 | 1.08 |
| Laundry | n/a | 1.8 |
| Dish wash | n/a | 3.54 |
| Total hygiene | 1.98 | 7.32 |
| **Total water consumption** | **4.48** | **9.82** |

- Footnote 91 in the BVAD: "Actual usage has been substantially less."
- For a 4-person crew: 4 x 4.48 = 17.9 kg water/day, 4 x 0.816 = 3.3 kg O2/day, 4 x 1.51 = 6.0 kg food/day (my arithmetic).

**Battery.** BVAD Table 3-15 (PDF p.52), lithium-ion with liquid electrolyte: cell energy density 200-300 Wh/L, **cell specific energy 100-150 Wh/kg**, 1,500 cycles, 60% depth of discharge, TRL 5 to 9. Solid-state concepts listed at 300-450 Wh/kg are TRL 1-3.
- A pack is heavier than its cells. I found no sourced cell-to-pack ratio (**UNSOURCED**). Assume 0.6-0.7 as a labelled assumption.
- Sizing example (my arithmetic): 125 Wh/kg x 0.65 pack factor x 0.6 DoD is about 49 Wh/kg usable. A 20 kWe base riding through a 12.3 h night needs about 246 kWh, or about 5,000 kg of battery. Per battery, "40 batteries" would be about 125 kg and 6 kWh usable each. Treat that as an illustration of the unit size, not a design.

**Habitat and base power**
- DRA 5.0 power paper (Cataldo, NASA GRC, Proceedings of Nuclear and Emerging Technologies for Space 2009, 2009-06, https://ntrs.nasa.gov/api/citations/20120012929/downloads/20120012929.pdf): "Nominal total load power for the crew phase is approximately 20 kWe, for both day and night operation." The habitat is "scaled for Mars based on a monolithic habitat design for the lunar South Pole with a crew of four." The paper's Table II (per-element values) is an image and was not readable, so I have no habitat-only kWe.
- Nuclear system around 30 kWe, versus solar peak about 100 kWe for the same loads, because the solar case needs night storage.
- Rucker (NASA, 2016-09): four landers with crew, nominal 31.9 kW day and 26.8 kW night. In a dust storm 22.9 kW day and 24.1 kW night. Dust storm loads drop because ISRU is cut. First-two-lander ISRU phase: 34.2 kW day, 35 kW night; dust storm 11.0 / 11.7 kW. The "dust storm" reduction (from about 35 to about 11 kW) is the NASA justification for load shedding.

## 7. Ice mining and ISRU power

- NASA design basis: 1.5 kg/hr water production, giving 0.67 kg/hr CH4 and 2.68 kg/hr O2 (Kleinhenz et al., NTRS 20180005542, 2018, slide 5). Environment: Jezero for hydrated minerals, Viking 2 site for ice.
- Water budget (Hoffman et al., 2017-03-04, NTRS 20170002074, slide 5): 25 t for open-loop life support of four crew for 500 days, 20 t for ascent propellant, 23 t for rover reactants. "16 tons/year of water extraction" would support a 500-day mission every four years.
- The Rodwell (Rodriguez Well) melts ice in a pool and pumps liquid water out. The Hoffman paper has an energy-to-melt graph (1000 kg of ice, -80/-50/-20 C) but no kW number I could read. My physics estimate is about 0.12 kWh per kg of -50 C ice before losses, so 1.5 kg/hr is about 0.18 kW thermal at minimum. Real wells need much more to keep the pool liquid. **UNSOURCED as a mission figure.**
- The dominant load is oxygen/propellant production: 66 kWe (8 h/day) or 22 kWe continuous in DRA 5.0 (Cataldo 2009). Shedding that load drops the base from about 96 kWe daytime to about 12 kWe (Cataldo). That is the quotable basis for "pause the ISRU plant in a dust storm".
- **Caveat for "shut the ice drill".** The NASA numbers above are for the oxygen plant, not an ice drill. I found **no sourced drill power**. If the demo says the ice drill saves power, label the figure as an assumption or use the ISRU plant numbers.
- MOXIE (secondary): 122 g total oxygen, peak 12 g/hr, 300 W (Wikipedia infobox). Use as a real flight-hardware data point, not a base number.

## JS-ready constants

```js
// Sources: see report sections. UNSOURCED items are marked.
export const MARS = {
  SOL_S: 88775.244,                 // Mars24 C-2: 1.0274912517 d x 86400
  SOL_DAYS_PER_EARTH_DAY: 1/1.0274912517,
  SYNODIC_DAYS: 779.94,             // NSSDC fact sheet 2025-05-19
  DIST_MIN_KM: 54.6e6, DIST_MAX_KM: 401.4e6,
  C_KM_S: 299792.458, AU_KM: 149597870.7, LIGHT_S_PER_AU: 499.004784,
  JEZERO: { lat: 18.38, lonE: 77.58, diameter_km: 45 },        // Wikipedia; frame not stated
  LANDING: { lat: 18.44, lonE: 77.45 },                          // Wikipedia; 4-decimal values UNSOURCED
  TAI_MINUS_UTC_S: 37,
};
// Horizons geocentric Mars range, AU (30-day steps, JPL Horizons, queried 2026-10-23)
export const HORIZONS_AU = [
  ['2026-10-23', 1.50406590604046], ['2026-11-22', 1.25575975804917],
  ['2026-12-22', 0.99576130116447], ['2027-01-21', 0.77315619630029],
  ['2027-02-20', 0.67791881744057], ['2027-03-22', 0.77156774563146],
  ['2027-04-21', 0.98792470688134], ['2027-05-21', 1.24007028580486],
];
export const lightMinOneWay = au => au * 499.004784 / 60;     // 12.51 min on 2026-10-23
// Opportunity dust model (fit to JPL pairs (1.0,468), (2.1,345), (10.5,21); 2018 array condition)
export const OPP = { E0_WH_SOL: 650, K: 0.31, AREA_M2: 1.3 /* UNSOURCED, secondary only */ };
export const energyWhPerSol = (tau, areaM2 = OPP.AREA_M2) =>
  OPP.E0_WH_SOL * Math.exp(-OPP.K * tau) * areaM2 / OPP.AREA_M2;
export const OPP_POINTS = [ // [tau, Wh/sol, source]
  [1.0, 468, 'JPL MER update 2018-06-12'], [2.1, 345, 'JPL MER update 2018-06-12'],
  [10.5, 21, 'JPL graphic 2018-06-13'], [4.12, 280, 'JPL 2007-07-17 (cleaner 2007 arrays)'],
];
// Crew, per crew-member-day (BVAD Rev1 2018, Tables 3-33 and 4-20)
export const CREW = { O2_KG: 0.816, FOOD_KG: 1.51, POTABLE_KG: 2.5, WATER_TOTAL_EARLY_KG: 4.48,
  WATER_TOTAL_MATURE_KG: 9.82, CO2_KG: 1.04 };
// Power (kW): Cataldo 2009 ~20 kWe crew-phase nominal; Rucker 2016 four-lander + crew loads
export const POWER_KW = { BASE_NOMINAL: 20, WITH_CREW_DAY: 31.915, WITH_CREW_NIGHT: 26.790,
  DUST_DAY: 22.945, DUST_NIGHT: 24.060, ISRU_O2_PLANT: 22 /* continuous equiv. */ };
export const BATTERY = { CELL_WH_KG: [100, 150], PACK_FACTOR: 0.65 /* ASSUMPTION */, DOD: 0.6 };
export const ISRU = { WATER_KG_HR: 1.5, MELT_KWH_PER_KG_MIN: 0.12 /* my physics, not sourced */ };
export const LAUNCH = { FH_PRICE_USD: [97e6, 150e6], FH_MARS_KG: 16800, FH_LEO_KG: 63800 };
```

Mars24 reference implementation (tested only for plausibility, see section 2): `/private/tmp/claude-502/-Users-TAITA-Projects-ares/68cb0f5f-9dae-4466-a672-556fa0e064e5/scratchpad/mars24.js`. Fit script: `.../scratchpad/fit.py` in the same folder.
