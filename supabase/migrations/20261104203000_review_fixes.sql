-- Fixes from an independent review.

-- Snapshots record whether the estimate could be trusted when it was captured.
alter table public.data_health_snapshots add column has_enough_data boolean;
update public.data_health_snapshots s
set has_enough_data = c.has_enough_data
from public.building_compliance c
where c.building_id = s.building_id;
alter table public.data_health_snapshots alter column has_enough_data set not null;

create or replace function private.capture_data_health() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  for v_id in select id from public.buildings loop
    perform private.refresh_building_alerts(v_id);
  end loop;

  insert into public.data_health_snapshots
    (building_id, completeness_pct, open_issues, reported_tco2e, adjusted_tco2e, reported_fine_usd, adjusted_fine_usd, has_enough_data)
  select c.building_id, c.completeness_pct,
         (select count(*) from public.alerts a where a.building_id = c.building_id and a.status = 'open'),
         c.reported_tco2e, c.adjusted_tco2e, c.reported_fine_usd, c.adjusted_fine_usd, c.has_enough_data
  from public.building_compliance c;

  -- Keep the table from growing forever.
  delete from public.data_health_snapshots where captured_at < now() - interval '90 days';
end $$;

-- Alerts only cover meters the building uses, and a missing reading no longer
-- claims an estimate exists, since a building can be below the data threshold.
create or replace function private.refresh_building_alerts(p_building_id uuid) returns void
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
         format('No %s reading for %s.',
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
  join public.buildings b on b.id = r.building_id
  where r.building_id = p_building_id and (r.fuel = 'electricity' or b.uses_natural_gas)
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
  join public.buildings b on b.id = r.building_id
  join public.meter_readings p
    on p.building_id = r.building_id and p.fuel = r.fuel
   and p.period_month = (r.period_month - interval '1 year')::date
  where r.building_id = p_building_id
    and (r.fuel = 'electricity' or b.uses_natural_gas)
    and r.period_month between v_start and v_end
    and p.quantity > 0
    and (r.quantity > p.quantity * 3 or r.quantity < p.quantity / 3);

  -- Out of range with no last year to compare to: far above the building's own
  -- median. Six times, because normal winter gas can reach four times the median.
  insert into pg_temp.wanted_alerts
  select 'out_of_range', 'warning', r.fuel, r.period_month,
         format('%s %s for %s is %s times this building''s typical month. Check for a typo.',
                to_char(r.quantity, 'FM999,999,999,990'), r.unit,
                to_char(r.period_month, 'FMMonth YYYY'),
                to_char(r.quantity / m.median_quantity, 'FM990.0'))
  from public.meter_readings r
  join public.buildings b on b.id = r.building_id
  join lateral (
    select percentile_cont(0.5) within group (order by x.quantity)::numeric as median_quantity,
           count(*) as n
    from public.meter_readings x
    where x.building_id = r.building_id and x.fuel = r.fuel
      and x.period_month between v_start and v_end
  ) m on true
  where r.building_id = p_building_id
    and (r.fuel = 'electricity' or b.uses_natural_gas)
    and r.period_month between v_start and v_end
    and m.n >= 3 and m.median_quantity > 0
    and r.quantity > m.median_quantity * 6
    and not exists (
      select 1 from public.meter_readings p
      where p.building_id = r.building_id and p.fuel = r.fuel
        and p.period_month = (r.period_month - interval '1 year')::date
    );

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

-- A new building has every month missing right away, not at the next scheduled run,
-- and turning gas on or off changes which meters are expected.
create function private.refresh_alerts_for_building() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.refresh_building_alerts(new.id);
  return null;
end $$;

create trigger refresh_alerts_on_insert after insert on public.buildings
  for each row execute function private.refresh_alerts_for_building();
create trigger refresh_alerts_on_gas_change after update of uses_natural_gas on public.buildings
  for each row when (old.uses_natural_gas is distinct from new.uses_natural_gas)
  execute function private.refresh_alerts_for_building();

revoke all on all functions in schema private from public, anon, authenticated;

-- Bring existing alerts up to date with the new wording.
do $$
declare v_id uuid;
begin
  for v_id in select id from public.buildings loop
    perform private.refresh_building_alerts(v_id);
  end loop;
end $$;
