# [PROJECT NAME]

> One-line pitch: [who] can [do what] so that [outcome]. Data stays clean automatically.

Built for the Supabase x Sodabase x BuilderBase NYC Hackathon (Nov 4, 2026).

## Problem

[1 to 2 sentences: the problem, who has it, why it matters. Fill in once the idea is chosen.]

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
- Frontend: [Next.js / React + Tailwind + shadcn/ui]
- Hosting: [Vercel / Netlify]

## Features (MVP, keep it small)

- [ ] Auth (sign up / log in)
- [ ] [Core flow 1]
- [ ] [Core flow 2]
- [ ] Data quality view in the UI (flag stale, empty or invalid records)
- [ ] Seeded realistic demo data

## Data model (2 to 4 tables)

| Table | Purpose | Key columns |
|-------|---------|-------------|
| `profiles` | Users | `id` (FK auth.users), `created_at`, `updated_at` |
| `[main_table]` | [core entity] | `id`, `user_id`, `...`, `created_at`, `updated_at` |
| `[events_table]` | [data that changes over time] | `id`, `[main_id]` FK, `value`, `recorded_at` |

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
- Edge functions for validation and background logic: [list them]

## Getting started

```bash
git clone [REPO URL]
cd [REPO NAME]
cp .env.example .env.local   # add SUPABASE_URL and SUPABASE_ANON_KEY
npm install
npm run dev
```

Apply the schema:

```bash
supabase link --project-ref [PROJECT_REF]
supabase db push
```

## Demo

- Live URL: [add]
- Demo video: [add]
- Sodabase Data Quality Score: [add]

## Timeline

- 4:30 to 5:00: schema, auth, Sodabase connected
- 5:00 to 6:15: core features, constraints, RLS, indexes
- 6:15 to 6:45: polish, deploy, seed data (feature freeze at 6:15)
- 6:45 to 7:00: video, README, submit

## Team

- [Name], [role]
- [Name], [role]

## Instructions for Claude

- Keep scope minimal: finish the MVP before adding anything.
- Always add constraints, RLS policies and indexes when creating a table.
- Write migrations as files in `/supabase/migrations`, never only in the dashboard.
- Prefer small, working increments; the app must run end to end at all times.
- Update this README (stack, schema, features) as decisions are made.