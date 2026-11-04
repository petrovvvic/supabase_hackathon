Yes, it’s a good pick. It’s real, local and easy to explain in one sentence, and the core problem (missing or stale meter readings making compliance numbers wrong) maps directly onto what Sodabase scores.

Why it works

The data changes monthly, so Sodabase has something to learn from.
There are natural rules to enforce: no negative usage, no gaps, plausible ranges, unit consistency.
RLS is easy to justify: each owner or manager sees only their own buildings.
The demo story is strong: “a missing reading turns a fine estimate from wrong to right.”

Risks

Domain rabbit hole. The real LL97 math has building-type limits, two compliance periods and several emission factors. Don’t model all of it.
Credibility. If the numbers look off, judges from NYC may notice. Label everything as an “estimate” and keep the factors in a config table you can cite.
Scope. A map, PDF reports and utility integrations are all traps for the next two hours.

How I’d scope it

4 tables: buildings, meter_readings (electricity, gas, month, kWh or therms), emission_factors (config), alerts.
Pick 3 building types with hardcoded limits and one compliance period. Verify the factors and the fine rate (I believe about $268 per ton over the limit) against the official NYC sources before you display them.
A single dashboard page per building showing: the emissions estimate against the limit, the fine risk, a data completeness bar (e.g. “10 of 12 months, electricity gap in March”), and a deadline countdown.
An edge function that validates each reading on insert (range check, duplicate month, unit) and creates an alert when a month is missing or stale.
Seed it with 5 to 10 realistic buildings, including a couple with deliberately messy data to show the flagging.

The pitch line: “Fines are calculated from meter data, and meter data is always incomplete. We make the gaps visible before the fine does.”

Want me to write the schema (tables, constraints, RLS, indexes) as a migration file and update the README? That would get you to a connected Sodabase fastest, since you’re already ten minutes into build time.