-- The seed backdated created_at to a month's billing date, which put October's
-- readings in the future (Nov 7). Only timestamps change here, never a quantity.
update public.meter_readings
set created_at = updated_at
where created_at > updated_at;

-- A row can't be created after it was last updated, on any table.
alter table public.profiles add constraint profiles_created_before_updated check (created_at <= updated_at);
alter table public.emission_factors add constraint emission_factors_created_before_updated check (created_at <= updated_at);
alter table public.emission_limits add constraint emission_limits_created_before_updated check (created_at <= updated_at);
alter table public.buildings add constraint buildings_created_before_updated check (created_at <= updated_at);
alter table public.meter_readings add constraint meter_readings_created_before_updated check (created_at <= updated_at);
alter table public.alerts add constraint alerts_created_before_updated check (created_at <= updated_at);
alter table public.data_health_snapshots add constraint data_health_snapshots_created_before_updated check (created_at <= updated_at);
