-- Meterproof: LL97 emissions estimates built on meter data that can be trusted.
-- Every table: constraints, RLS, indexed foreign keys, updated_at trigger.

create schema if not exists private;
revoke all on schema private from public;

create function private.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 1 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
                           split_part(new.email, '@', 1), 'Building manager'));
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- ---------------------------------------------------------------- config
create table public.emission_factors (
  id bigint generated always as identity primary key,
  fuel text not null check (fuel in ('electricity', 'natural_gas')),
  unit text not null check (unit in ('kWh', 'therm')),
  tco2e_per_unit numeric(12, 9) not null check (tco2e_per_unit > 0),
  period_start_year int not null check (period_start_year >= 2024),
  period_end_year int not null,
  source_url text not null check (source_url like 'https://%'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (fuel, period_start_year),
  check (period_end_year >= period_start_year),
  check ((fuel = 'electricity' and unit = 'kWh') or (fuel = 'natural_gas' and unit = 'therm'))
);

create table public.emission_limits (
  id bigint generated always as identity primary key,
  occupancy_group text not null check (occupancy_group in ('B', 'R-1', 'R-2')),
  description text not null check (length(trim(description)) > 0),
  tco2e_per_sf numeric(8, 5) not null check (tco2e_per_sf > 0),
  penalty_usd_per_tco2e numeric(8, 2) not null check (penalty_usd_per_tco2e > 0),
  period_start_year int not null check (period_start_year >= 2024),
  period_end_year int not null,
  source_url text not null check (source_url like 'https://%'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (occupancy_group, period_start_year),
  check (period_end_year >= period_start_year)
);

-- ---------------------------------------------------------------- buildings
create table public.buildings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  address text not null check (length(trim(address)) between 5 and 200),
  occupancy_group text not null check (occupancy_group in ('B', 'R-1', 'R-2')),
  gross_floor_area_sf int not null check (gross_floor_area_sf > 25000),
  uses_natural_gas boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, address)
);
create index buildings_owner_id_idx on public.buildings (owner_id);
create index buildings_occupancy_group_idx on public.buildings (occupancy_group);

-- ---------------------------------------------------------------- meter_readings
create table public.meter_readings (
  id uuid primary key default gen_random_uuid(),
  building_id uuid not null references public.buildings (id) on delete cascade,
  fuel text not null check (fuel in ('electricity', 'natural_gas')),
  period_month date not null check (extract(day from period_month) = 1 and period_month >= date '2020-01-01'),
  quantity numeric(14, 2) not null check (quantity >= 0),
  unit text not null check (unit in ('kWh', 'therm')),
  source text not null default 'manual_entry' check (source in ('manual_entry', 'utility_bill')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (building_id, fuel, period_month),
  check ((fuel = 'electricity' and unit = 'kWh') or (fuel = 'natural_gas' and unit = 'therm'))
);
create index meter_readings_period_month_idx on public.meter_readings (period_month);

-- ---------------------------------------------------------------- alerts
create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  building_id uuid not null references public.buildings (id) on delete cascade,
  kind text not null check (kind in ('missing_reading', 'stale_data', 'out_of_range')),
  severity text not null check (severity in ('warning', 'critical')),
  fuel text not null check (fuel in ('electricity', 'natural_gas')),
  period_month date not null check (extract(day from period_month) = 1),
  message text not null check (length(trim(message)) > 0),
  status text not null default 'open' check (status in ('open', 'resolved')),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'resolved') = (resolved_at is not null))
);
create index alerts_building_status_idx on public.alerts (building_id, status);
create unique index alerts_one_open_per_issue_idx on public.alerts (building_id, kind, fuel, period_month)
  where status = 'open';

-- ---------------------------------------------------------------- updated_at
create trigger set_updated_at before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.emission_factors
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.emission_limits
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.buildings
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.meter_readings
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.alerts
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------- reading guard
-- Runs even if a client bypasses the edge function and writes through the API.
create function private.reject_future_reading() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.period_month >= date_trunc('month', now())::date then
    raise exception 'Reading for % is not a completed month', new.period_month
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger reject_future_reading before insert or update on public.meter_readings
  for each row execute function private.reject_future_reading();

-- ---------------------------------------------------------------- alert engine
-- Recomputes the issues for one building from its readings, then opens what is
-- new and resolves what has been fixed. Alerts are never written by clients.
create function private.refresh_building_alerts(p_building_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_end date := (date_trunc('month', now()) - interval '1 month')::date;
  v_start date := (date_trunc('month', now()) - interval '12 months')::date;
begin
  create temp table if not exists pg_temp.wanted_alerts (
    kind text, severity text, fuel text, period_month date, message text
  ) on commit drop;
  truncate pg_temp.wanted_alerts;

  with fuels as (
    select b.id, f.fuel
    from public.buildings b
    cross join lateral (values ('electricity'), ('natural_gas')) as f (fuel)
    where b.id = p_building_id and (f.fuel = 'electricity' or b.uses_natural_gas)
  ), months as (
    select m::date as period_month
    from generate_series(v_start, v_end, interval '1 month') as m
  )
  insert into pg_temp.wanted_alerts
  select 'missing_reading', 'critical', f.fuel, m.period_month,
         format('No %s reading for %s, so the estimate is using a substitute value.',
                replace(f.fuel, '_', ' '), to_char(m.period_month, 'FMMonth YYYY'))
  from fuels f cross join months m
  where not exists (
    select 1 from public.meter_readings r
    where r.building_id = f.id and r.fuel = f.fuel and r.period_month = m.period_month
  );

  -- Stale: the newest reading for a fuel is more than one billing cycle behind.
  insert into pg_temp.wanted_alerts
  select 'stale_data', 'warning', r.fuel, max(r.period_month),
         format('Last %s reading is from %s. Check the utility feed or the last bill.',
                replace(r.fuel, '_', ' '), to_char(max(r.period_month), 'FMMonth YYYY'))
  from public.meter_readings r
  where r.building_id = p_building_id
  group by r.fuel
  having max(r.period_month) < v_end - interval '1 month';

  -- Out of range: far from the same month last year, which allows for seasons.
  insert into pg_temp.wanted_alerts
  select 'out_of_range', 'warning', r.fuel, r.period_month,
         format('%s %s for %s is %s times the same month last year. Check for a typo.',
                to_char(r.quantity, 'FM999,999,999,990'), r.unit,
                to_char(r.period_month, 'FMMonth YYYY'),
                to_char(r.quantity / p.quantity, 'FM990.0'))
  from public.meter_readings r
  join public.meter_readings p
    on p.building_id = r.building_id and p.fuel = r.fuel
   and p.period_month = (r.period_month - interval '1 year')::date
  where r.building_id = p_building_id
    and r.period_month between v_start and v_end
    and p.quantity > 0
    and (r.quantity > p.quantity * 3 or r.quantity < p.quantity / 3);

  update public.alerts a
  set status = 'resolved', resolved_at = now()
  where a.building_id = p_building_id and a.status = 'open'
    and not exists (
      select 1 from pg_temp.wanted_alerts w
      where w.kind = a.kind and w.fuel = a.fuel and w.period_month = a.period_month
    );

  insert into public.alerts (building_id, kind, severity, fuel, period_month, message)
  select p_building_id, w.kind, w.severity, w.fuel, w.period_month, w.message
  from pg_temp.wanted_alerts w
  on conflict (building_id, kind, fuel, period_month) where status = 'open'
  do update set message = excluded.message, severity = excluded.severity
  where alerts.message is distinct from excluded.message;
end $$;

create function private.refresh_alerts_after_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  for v_id in select distinct building_id from new_rows loop
    perform private.refresh_building_alerts(v_id);
  end loop;
  return null;
end $$;

create function private.refresh_alerts_after_update() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  for v_id in select building_id from new_rows union select building_id from old_rows loop
    perform private.refresh_building_alerts(v_id);
  end loop;
  return null;
end $$;

create function private.refresh_alerts_after_delete() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  -- Skip buildings that are themselves being deleted (cascade).
  for v_id in select distinct o.building_id from old_rows o
              join public.buildings b on b.id = o.building_id loop
    perform private.refresh_building_alerts(v_id);
  end loop;
  return null;
end $$;

create trigger refresh_alerts_insert after insert on public.meter_readings
  referencing new table as new_rows
  for each statement execute function private.refresh_alerts_after_insert();
create trigger refresh_alerts_update after update on public.meter_readings
  referencing old table as old_rows new table as new_rows
  for each statement execute function private.refresh_alerts_after_update();
create trigger refresh_alerts_delete after delete on public.meter_readings
  referencing old table as old_rows
  for each statement execute function private.refresh_alerts_after_delete();

revoke all on all functions in schema private from public, anon, authenticated;

-- ---------------------------------------------------------------- compliance view
-- One calculation shared by every screen. security_invoker keeps RLS in force.
-- Window: trailing 12 completed months, so all seasons are always covered.
create view public.building_compliance with (security_invoker = true) as
with bounds as (
  select (date_trunc('month', now()) - interval '12 months')::date as window_start,
         (date_trunc('month', now()) - interval '1 month')::date as window_end
), fuels as (
  select b.id as building_id, f.fuel
  from public.buildings b
  cross join lateral (values ('electricity'), ('natural_gas')) as f (fuel)
  where f.fuel = 'electricity' or b.uses_natural_gas
), months as (
  select m::date as period_month, w.window_start, w.window_end
  from bounds w
  cross join generate_series(w.window_start, w.window_end, interval '1 month') as m
), per_month as (
  -- A missing month is filled from the same month last year, because usage is
  -- seasonal, and only then from the average of the months that were reported.
  select f.building_id, f.fuel, r.quantity as reported, py.quantity as prior_year,
         avg(r.quantity) over (partition by f.building_id, f.fuel) as avg_reported
  from fuels f
  cross join months m
  left join public.meter_readings r
    on r.building_id = f.building_id and r.fuel = f.fuel and r.period_month = m.period_month
  left join public.meter_readings py
    on py.building_id = f.building_id and py.fuel = f.fuel
   and py.period_month = (m.period_month - interval '1 year')::date
), per_fuel as (
  select building_id, fuel,
         count(reported)::int as reported_months,
         count(*)::int as expected_months,
         coalesce(sum(reported), 0) as reported_quantity,
         coalesce(sum(coalesce(reported, prior_year, avg_reported)), 0) as adjusted_quantity
  from per_month
  group by building_id, fuel
), emissions as (
  select p.building_id,
         sum(p.reported_months)::int as reported_readings,
         sum(p.expected_months)::int as expected_readings,
         sum(p.reported_quantity * e.tco2e_per_unit) as reported_tco2e,
         sum(p.adjusted_quantity * e.tco2e_per_unit) as adjusted_tco2e
  from per_fuel p
  join public.emission_factors e on e.fuel = p.fuel and e.period_start_year = 2024
  group by p.building_id
)
select b.id as building_id,
       w.window_start,
       w.window_end,
       em.reported_readings,
       em.expected_readings,
       round(100.0 * em.reported_readings / em.expected_readings, 1) as completeness_pct,
       round(em.reported_tco2e, 1) as reported_tco2e,
       round(em.adjusted_tco2e, 1) as adjusted_tco2e,
       round(b.gross_floor_area_sf * l.tco2e_per_sf, 1) as limit_tco2e,
       round(greatest(em.reported_tco2e - b.gross_floor_area_sf * l.tco2e_per_sf, 0) * l.penalty_usd_per_tco2e, 0) as reported_fine_usd,
       round(greatest(em.adjusted_tco2e - b.gross_floor_area_sf * l.tco2e_per_sf, 0) * l.penalty_usd_per_tco2e, 0) as adjusted_fine_usd
from public.buildings b
cross join bounds w
join emissions em on em.building_id = b.id
join public.emission_limits l on l.occupancy_group = b.occupancy_group and l.period_start_year = 2024;

-- ---------------------------------------------------------------- RLS
alter table public.profiles enable row level security;
alter table public.emission_factors enable row level security;
alter table public.emission_limits enable row level security;
alter table public.buildings enable row level security;
alter table public.meter_readings enable row level security;
alter table public.alerts enable row level security;

create policy "read own profile" on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy "update own profile" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "read factors" on public.emission_factors for select to authenticated using (true);
create policy "read limits" on public.emission_limits for select to authenticated using (true);

create policy "manage own buildings" on public.buildings for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy "manage readings of own buildings" on public.meter_readings for all to authenticated
  using (exists (select 1 from public.buildings b where b.id = building_id and b.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.buildings b where b.id = building_id and b.owner_id = (select auth.uid())));

create policy "read alerts of own buildings" on public.alerts for select to authenticated
  using (exists (select 1 from public.buildings b where b.id = building_id and b.owner_id = (select auth.uid())));

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.emission_factors, public.emission_limits, public.alerts, public.building_compliance to authenticated;
grant select, insert, update, delete on public.buildings, public.meter_readings to authenticated;

-- ---------------------------------------------------------------- reference data
-- Sources: NYC Admin Code 28-320 limits and 2024-2029 coefficients as published.
insert into public.emission_factors (fuel, unit, tco2e_per_unit, period_start_year, period_end_year, source_url) values
  ('electricity', 'kWh', 0.000288962, 2024, 2029, 'https://www.nyc.gov/assets/buildings/pdf/ll97_enforce-web.pdf'),
  -- 0.00005311 tCO2e per kBtu; 1 therm = 100 kBtu.
  ('natural_gas', 'therm', 0.005311, 2024, 2029, 'https://www.nyc.gov/assets/buildings/pdf/ll97_enforce-web.pdf');

insert into public.emission_limits (occupancy_group, description, tco2e_per_sf, penalty_usd_per_tco2e, period_start_year, period_end_year, source_url) values
  ('B', 'Office', 0.00846, 268, 2024, 2029, 'https://www.nyc.gov/assets/buildings/pdf/ll97_enforce-web.pdf'),
  ('R-1', 'Hotel', 0.00987, 268, 2024, 2029, 'https://www.nyc.gov/assets/buildings/pdf/ll97_enforce-web.pdf'),
  ('R-2', 'Multifamily', 0.00675, 268, 2024, 2029, 'https://www.nyc.gov/assets/buildings/pdf/ll97_enforce-web.pdf');
