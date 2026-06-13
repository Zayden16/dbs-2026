# Bericht Audit & TODO — deadline TOMORROW

Status of the codebase: **SQL ⇄ MongoDB reconciled and verified live** (canonical
table below). Most open items are in the **Bericht document** (stale numbers,
contradictions, placeholders), not the code. Corsin (Kap. 7 / Metabase) has gone
dark — assume Yazdan covers the viz queries (now in `metabase/`).

**Canonical result (verified — use everywhere):**

| country | ice €/km | ev €/km | ev CO₂ | ice CO₂ | rec |
|---|---|---|---|---|---|
| CH | 0.1740 | 0.0375 | 6.91  | 235 | 1 |
| DE | 0.1810 | 0.0684 | 77.84 | 235 | 1 |
| FR | 0.1775 | 0.0470 | 14.57 | 235 | 1 |

---

## P0 — Wrong/contradictory (fix first, they're factual errors)

- [x] **Kap. 5.1 SQL result table updated** to the canonical values + real EV/ICE ratios (CH 0.22/0.03, DE 0.38/0.33, FR 0.26/0.06); `03_ev_ice_decision.sql` + `analytics_view` reproduce it exactly. *(Abb. 15 caption says "Screenshot DBeaver" — re-shoot from DBeaver so the figure is a real screenshot, optional.)*
- [x] **`analytics_view` now exists** — created live (`sql/07_create_analytics_view.sql`), the SQL analogue of Mongo's `mv_ev_decision`, read by Metabase. `SELECT * FROM analytics_view` reproduces the canonical table.
- [x] **Kap. 5.1 + 7.1.1 query snippets: column names fixed** to match the view (`ice_eur_per_km … recommend_ev, ratio_cost, ratio_co2`); `FROM analytics_view` kept.
- [x] **Kap. 7.1.1 `WHERE country_code = {{country}}`** (variable form).
- [ ] **Kap. 7.1 prose contradicts the result.** "Bei 15000 km … überwiegen in der Schweiz die höheren Anschaffungskosten …" implies EV NOT worth it in CH, but `recommend_ev=1` for CH and Kap. 7.1.4 says EV recommended. Rewrite to: EV recommended in all 3 countries (cost-ratio <110 %, CO₂-ratio <100 %); acquisition-price caveat is the indicative TCO chart only.
- [x] **Kap. 5.2 Mongo snippet: `fuel_type` filter added** to Stage 1 `$match` (`fuel_type: { $in: ["Petrol","Diesel"] }`) + stage-list description — now consistent with the 235 result and `04_analytics.js`.
- [ ] **Kap. 5 metric definition:** "ICE Kosten: … × Kraftstoffpreis des Landes" (singular) — actual = mean of petrol & diesel. Reword to `(Benzin+Diesel)/2`.

## P1 — Stale numbers / inaccurate mechanism

- [ ] **Kap. 4.3.1 currency claim false:** "Umrechnung aller vorliegenden Preise in CHF" — prices are in EUR (cost/km labelled €/km). Remove or correct.
- [ ] **Abb. 12 caption row counts are old:** "vehicle: 1'218, ice_emission: 173, ev_spec: 11". After reconciliation: `ice_emission`=7385, Petrol+Diesel fleet=3812, `ev_spec`=32, `vehicle`≈8600. Re-shoot the screenshot / update caption. *(run `sql/03_verify_row_counts.sql`.)*
- [ ] **Kap. 4.3.1 fuel-price mechanism:** says values "aus fuel_prices.csv extrahiert … in country eingefügt". SQL loader sets them as `INSERT … VALUES` constants (now matching the CSV); MongoDB reads `stg_fuel_prices`. Note this honestly (SQL has no `stg_fuel_prices`).
- [ ] **Abb. 13 / Abb. 14 Mongo counts:** verify "vehicles: 8'670, country_year_data: 78, charging_stations: 38'071" against live DB; update if changed after re-transform.
- [ ] **Kap. 4.1.2 Zugangsdaten:** MySQL table says `Database: railway` but connection string ends `/ev_project`. Use `ev_project` consistently (the ILIAS correction email). NOTE: live credentials are printed in the report — required for the "checkable online system", but they're in the repo `.env` (gitignored), do NOT also commit them in any md.

## P2 — Placeholders / structure (Kap. 7, Corsin's part)

- [ ] **Kap. 7.1.4 Action** is `[TODO]` — fill: EV recommended in CH/DE/FR (ratios), plus a 1-line sensitivity note (how recommendation shifts if electricity/fuel price changes).
- [ ] **Kap. 7.1.5 "(fix title) Personas"** empty — resolve each persona (Stefan/CH, Lisa/DE, Marc/FR) with its `mv_ev_decision` line, or trim the 3-persona framing in Kap. 2.4.
- [ ] **Broken numbering:** `7.1.5` → `7.2 (break even/` → `8.2 [TODO]`. Renumber cleanly (7.1.x under 7.1; real second use case = 7.2; Fazit = 8).
- [ ] **Kap. 4.1.1 Datenflüsse** has `[TODO: draw.io]` — either keep ASCII (fine) or redraw; remove the TODO marker.
- [ ] **Q5 numbering:** Kap. 7.1.2 lists Q1,Q2,Q3,Q4,Q6 (Q5 = charging, skipped); Kap. 8.2 TODO cites Q5. Q5 exists in `metabase/mongodb_native_queries.md` — add it or fix the cross-ref.
- [ ] **Dashboard screenshots** (Abb. 24–28) — capture from Metabase once panels built from `metabase/` queries.

## P3 — Scope/framing (lower risk, do if time)

- [ ] **Kap. 1 / 2.1 "TCO" framing vs delivery:** Kap. 2 promises full LCA, break-even, segments, subsidies, green-charging, maintenance, depreciation — none delivered (analysis = operating cost/km + grid CO₂). Add one "Abgrenzung/Scope" sentence narrowing it, or move the unbuilt items to "Ausblick".
- [ ] **Kap. 8.2 TODO** lists future use cases (break-even, charging density, EV adoption) — decide keep-as-ausblick vs build (break-even is feasible: have grid CO₂ + consumption; only the battery CO₂-backpack input is missing).
- [ ] Title page typos: "Real Team Name 1", "Corsin Hidbeer" (→ Hidber).

## Done (code) ✅

- [x] SQL ⇄ Mongo reconciled: real fuel prices, full 3812 ICE fleet in 3NF tables, EV 1dp rounding, unified `(petrol+diesel)/2` formula. Verified live.
- [x] Repo prepped for GitHub: secrets → `.env`, reorg, README.
- [x] Metabase queries extracted to `metabase/` (MQL + SQL, paste-ready).
