-- Enforce reading rules in the database too, so direct API writes can't skip them.
alter table public.meter_readings
  add constraint meter_readings_quantity_not_nan check (quantity <> 'NaN');

create function private.validate_reading() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_building public.buildings%rowtype;
  v_ceiling numeric;
begin
  if new.period_month >= date_trunc('month', now())::date then
    raise exception 'Reading for % is not a completed month', new.period_month
      using errcode = 'check_violation';
  end if;

  select * into v_building from public.buildings where id = new.building_id;
  if not found then
    return new; -- The foreign key or RLS rejects this write.
  end if;

  if new.fuel = 'natural_gas' and not v_building.uses_natural_gas then
    raise exception 'This building is not set up for natural gas'
      using errcode = 'check_violation';
  end if;

  -- Same ceiling as the submit-reading edge function.
  v_ceiling := v_building.gross_floor_area_sf * case new.fuel when 'electricity' then 20 else 1 end;
  if new.quantity > v_ceiling then
    raise exception 'Reading of % % is above the limit of % for this building', new.quantity, new.unit, v_ceiling
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger reject_future_reading on public.meter_readings;
drop function private.reject_future_reading();

create trigger validate_reading before insert or update on public.meter_readings
  for each row execute function private.validate_reading();

revoke all on function private.validate_reading() from public, anon, authenticated;
