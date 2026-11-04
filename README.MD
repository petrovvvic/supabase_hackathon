# Meterproof

> NYC building managers can see what missing or mistyped meter readings do to their Local Law 97 fine estimate, before they file.

Built for the Supabase x Sodabase x BuilderBase NYC Hackathon (Nov 4, 2026).

## Problem

Under NYC's Local Law 97, large buildings pay $268 for every ton of carbon over their limit, and that bill is calculated from monthly meter readings. Those readings go missing and get mistyped, so managers find out too late that their numbers were wrong. In our sample data, two missing winter gas bills make a building that's on track for a $26,000 fine look like it owes nothing.

**Meterproof shows the gaps before the fine does.**

## Hackathon rules (context for Claude)

**Deadlines**
- 5:30 PM ET: Sodabase must be connected (connect earlier, it needs time to learn how tables change)
- 7:00 PM ET: submission closes on BuilderBase

**Submission requires**
- Public GitHub repo
- Demo video or live URL that shows the app working end to end
- Sodabase Data Quality Score

**Judging (25% each)**
1. Data quality: Sodabase score and how well the app keeps data clean
2. Built to scale: schema, indexes, row-level security, edge functions
3. Execution: demo works end to end
4. Craft: polish, originality, clear problem

## Tech stack

- Supabase: Postgres, Auth, Storage, Edge Functions
- Sodabase: data quality monitoring
- Frontend: Next.js, React, Tailwind
- Hosting: Vercel

## Features

- [x] Auth (sign up / log in)
- [x] Portfolio: fine estimate from reported data next to the estimate with gaps filled
- [x] Building page: 12-month readings grid, open issues, emissions against the limit
- [x] Add or correct a reading, validated by an edge function
- [x] Alerts open and resolve themselves as readings change
- [x] Seeded fictional portfolio of 8 buildings

Demo login: `demo@meterproof.app` / `meterproof-demo`. All readings are invented. Addresses are too, except 307 West 38th Street, where the hackathon took place; only its floor area is real.

## How the estimate works

- Window: trailing 12 completed months, so every season is covered.
- Emissions: usage x LL97 coefficient (2024-2029). Electricity 0.000288962 tCO2e/kWh, natural gas 0.00005311 tCO2e/kBtu (0.005311 per therm).
- Limits: office (B) 0.00846, hotel (R-1) 0.00987, multifamily (R-2) 0.00675 tCO2e/sf. Fine: $268 per ton over the limit.
- Missing months are filled from the same month last year, then from the average of reported months.
- These are estimates, not filings. Real LL97 reports also handle mixed occupancy, other fuels and deductions, which are out of scope. Each factor and limit row stores its source URL.

## Data model

| Table | Purpose | Key columns |
|-------|---------|-------------|
| `profiles` | Users, created on signup | `id` (FK auth.users), `full_name` |
| `buildings` | Covered buildings | `owner_id`, `address`, `occupancy_group`, `gross_floor_area_sf`, `uses_natural_gas` |
| `meter_readings` | Monthly usage | `building_id`, `fuel`, `period_month`, `quantity`, `unit`, `source` |
| `alerts` | Data issues, written only by the database | `building_id`, `kind`, `severity`, `fuel`, `period_month`, `status` |
| `data_health_snapshots` | Each building's data health over time, written by the scheduled job | `building_id`, `captured_at`, `completeness_pct`, `open_issues`, `adjusted_fine_usd` |
| `emission_factors` | LL97 coefficients (config) | `fuel`, `unit`, `tco2e_per_unit`, `source_url` |
| `emission_limits` | LL97 limits and fine rate (config) | `occupancy_group`, `tco2e_per_sf`, `penalty_usd_per_tco2e`, `source_url` |

`building_compliance` is a `security_invoker` view holding the one calculation every screen uses.

## Data quality rules (protects the Sodabase score)

- NOT NULL, CHECK, UNIQUE and foreign key constraints on every table
- Sensible defaults; no empty tables or unused columns
- `updated_at` trigger on all tables so rows never look stale
- Edge function validates input before it reaches the database
- Realistic seed data only (no "test123" rows)
- Keep real activity flowing after connecting Sodabase (updates, new rows)

## Built to scale

- Row-level security enabled on every table, policies based on `auth.uid()`
- Indexes on all foreign keys and on columns used to filter or sort
- Normalized schema; migrations committed in `/supabase/migrations`
- Edge function `submit-reading`: validates format, completed month, unit and a size-based ceiling, then writes with the caller's JWT so RLS still applies
- Alert engine in private Postgres functions, run by statement-level triggers so bulk loads recompute once per building
- Scheduled job `capture-data-health` (pg_cron): refreshes alerts so a newly missed month gets flagged, and records each building's health in `data_health_snapshots`. It runs every 15 minutes, which is faster than the product needs, so Sodabase has steady real data to learn from during the hackathon. Daily would be enough in production

## Getting started

```bash
git clone https://github.com/petrovvvic/supabase_hackathon.git
cd supabase_hackathon
cp .env.example .env.local   # add NEXT_PUBLIC_SUPABASE_ANON_KEY
npm install
npm run dev
```

Apply the schema:

```bash
npx supabase link --project-ref xtveantrlwgtsnxpgyxz
npx supabase db push --remote --include-seed
npx supabase functions deploy submit-reading
```

## Demo

- Live URL: https://meterproof-rust.vercel.app
- Demo video: [add]
- Sodabase Data Quality Score: [add]

## Timeline

- 4:30 to 5:00: schema, auth, Sodabase connected
- 5:00 to 6:15: core features, constraints, RLS, indexes
- 6:15 to 6:45: polish, deploy, seed data (feature freeze at 6:15)
- 6:45 to 7:00: video, README, submit

## Team

- Andrei Piatrouski

## Instructions for Claude

- Keep scope minimal: finish the MVP before adding anything.
- Always add constraints, RLS policies and indexes when creating a table.
- Write migrations as files in `/supabase/migrations`, never only in the dashboard.
- Prefer small, working increments; the app must run end to end at all times.
- Update this README (stack, schema, features) as decisions are made.