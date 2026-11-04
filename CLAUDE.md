@AGENTS.md

# Project notes

## Hackathon rules

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

## Instructions for Claude

- Keep scope minimal: finish the MVP before adding anything.
- Always add constraints, RLS policies and indexes when creating a table.
- Write migrations as files in `/supabase/migrations`, never only in the dashboard.
- Prefer small, working increments; the app must run end to end at all times.
- Update this README (stack, schema, features) as decisions are made.
