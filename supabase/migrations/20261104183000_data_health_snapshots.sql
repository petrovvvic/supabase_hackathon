-- Scheduled health check: refreshes alerts so a newly missed month is flagged
-- without waiting for someone to edit a reading, and records each building's
-- data health over time. Runs every 15 minutes, faster than the product needs,
-- so Sodabase has steady real data to learn from during the hackathon.
create extension if not exists pg_cron;

create table public.data_health_snapshots (
  id uuid primary key default gen_random_uuid(),
  building_id uuid not null references public.buildings (id) on delete cascade,
  captured_at timestamptz not null default now(),
  completeness_pct numeric(4, 1) not null check (completeness_pct between 0 and 100),
  open_issues int not null check (open_issues >= 0),
  reported_tco2e numeric(12, 1) not null check (reported_tco2e >= 0),
  adjusted_tco2e numeric(12, 1) not null check (adjusted_tco2e >= 0),
  reported_fine_usd numeric(14, 0) not null check (reported_fine_usd >= 0),
  adjusted_fine_usd numeric(14, 0) not null check (adjusted_fine_usd >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (building_id, captured_at)
);
create index data_health_snapshots_captured_at_idx on public.data_health_snapshots (captured_at);

create trigger set_updated_at before update on public.data_health_snapshots
  for each row execute function private.set_updated_at();

alter table public.data_health_snapshots enable row level security;

create policy "read snapshots of own buildings" on public.data_health_snapshots for select to authenticated
  using (exists (select 1 from public.buildings b where b.id = building_id and b.owner_id = (select auth.uid())));

revoke all on public.data_health_snapshots from anon, authenticated;
grant select on public.data_health_snapshots to authenticated;

create function private.capture_data_health() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  for v_id in select id from public.buildings loop
    perform private.refresh_building_alerts(v_id);
  end loop;

  -- A building with no readings yet still gets a row (0% complete).
  insert into public.data_health_snapshots
    (building_id, completeness_pct, open_issues, reported_tco2e, adjusted_tco2e, reported_fine_usd, adjusted_fine_usd)
  select c.building_id, c.completeness_pct,
         (select count(*) from public.alerts a where a.building_id = c.building_id and a.status = 'open'),
         c.reported_tco2e, c.adjusted_tco2e, c.reported_fine_usd, c.adjusted_fine_usd
  from public.building_compliance c;
end $$;

revoke all on function private.capture_data_health() from public, anon, authenticated;

select private.capture_data_health();
select cron.schedule('capture-data-health', '*/15 * * * *', 'select private.capture_data_health()');
