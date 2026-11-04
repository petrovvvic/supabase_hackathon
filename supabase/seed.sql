-- Sample portfolio for the demo. All readings are invented, as are the addresses except 307 West 38th.
-- Demo login: demo@meterproof.app / meterproof-demo
do $$
declare
  v_user uuid := '7a1f3c52-9b0e-4d6a-8c21-5e0f4b7d1a90';
begin
  if exists (select 1 from auth.users where id = v_user) then
    return;
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated',
          'demo@meterproof.app', extensions.crypt('meterproof-demo', extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', '{"full_name":"Dana Reyes"}', now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_user, v_user::text,
          jsonb_build_object('sub', v_user::text, 'email', 'demo@meterproof.app', 'email_verified', true),
          'email', now(), now(), now());

  create temp table seed_buildings (
    id uuid, name text, address text, occ text, sf int, gas boolean, kwh_sf numeric, therm_sf numeric, source text
  ) on commit drop;

  insert into seed_buildings values
    ('11111111-0000-4000-8000-000000000001', 'Hudson Crossing', '412 Greenwich Terrace, Manhattan, NY 10013', 'B', 186000, true, 15.5, 0.22, 'utility_bill'),
    ('11111111-0000-4000-8000-000000000002', 'The Marlowe', '88 Linden Row, Brooklyn, NY 11217', 'R-2', 104000, true, 5.2, 1.15, 'utility_bill'),
    ('11111111-0000-4000-8000-000000000003', 'Astor Court Apartments', '2150 Ellery Parkway, Bronx, NY 10462', 'R-2', 78000, true, 4.8, 0.74, 'manual_entry'),
    ('11111111-0000-4000-8000-000000000004', 'Northline Hotel', '305 Vesper Street, Manhattan, NY 10018', 'R-1', 142000, true, 19.0, 0.55, 'utility_bill'),
    ('11111111-0000-4000-8000-000000000005', 'Queensbridge Exchange', '47-20 Calder Avenue, Queens, NY 11101', 'B', 231000, false, 21.0, 0, 'utility_bill'),
    ('11111111-0000-4000-8000-000000000006', 'Fulton Lofts', '719 Ardent Place, Brooklyn, NY 11238', 'R-2', 62000, true, 5.6, 0.60, 'manual_entry'),
    ('11111111-0000-4000-8000-000000000007', 'Tillary Plaza', '160 Tobin Square, Brooklyn, NY 11201', 'B', 128000, true, 13.8, 0.19, 'manual_entry'),
    ('11111111-0000-4000-8000-000000000008', 'Riverside Gardens', '3401 Palisade Walk, Bronx, NY 10463', 'R-2', 91000, true, 4.6, 0.82, 'utility_bill');

  insert into public.buildings (id, owner_id, name, address, occupancy_group, gross_floor_area_sf, uses_natural_gas)
  select id, v_user, name, address, occ, sf, gas from seed_buildings;

  perform setseed(0.97);

  -- 24 months of history with seasonal curves and a little billing noise.
  create temp table seed_readings on commit drop as
  select b.id as building_id, f.fuel, m::date as period_month, f.unit, b.source,
         round((b.sf * case f.fuel when 'electricity' then b.kwh_sf else b.therm_sf end)
               * (case f.fuel
                    when 'electricity' then (array[.078,.073,.076,.074,.084,.098,.112,.112,.094,.077,.072,.075])[extract(month from m)::int]
                    else (array[.205,.185,.150,.085,.035,.015,.010,.010,.015,.050,.095,.155])[extract(month from m)::int]
                  end)
               * (0.96 + random()::numeric * 0.08), 0) as quantity
  from seed_buildings b
  cross join lateral (values ('electricity', 'kWh'), ('natural_gas', 'therm')) as f (fuel, unit)
  cross join generate_series(date_trunc('month', now()) - interval '24 months',
                             date_trunc('month', now()) - interval '1 month', interval '1 month') as m
  where f.fuel = 'electricity' or b.gas;

  -- The Marlowe: two winter gas bills missing. Looks compliant until the gap is filled.
  delete from seed_readings
  where building_id = '11111111-0000-4000-8000-000000000002' and fuel = 'natural_gas'
    and period_month in (date_trunc('month', now() - interval '10 months')::date,
                         date_trunc('month', now() - interval '9 months')::date);

  -- Astor Court: March electricity missing.
  delete from seed_readings
  where building_id = '11111111-0000-4000-8000-000000000003' and fuel = 'electricity'
    and period_month = date_trunc('month', now() - interval '8 months')::date;

  -- Fulton Lofts: nothing since the summer.
  delete from seed_readings
  where building_id = '11111111-0000-4000-8000-000000000006'
    and period_month > date_trunc('month', now() - interval '5 months')::date;

  -- Tillary Plaza: an extra digit typed into one electricity reading.
  update seed_readings set quantity = quantity * 10
  where building_id = '11111111-0000-4000-8000-000000000007' and fuel = 'electricity'
    and period_month = date_trunc('month', now() - interval '4 months')::date;

  insert into public.meter_readings (building_id, fuel, period_month, quantity, unit, source, created_at)
  select building_id, fuel, period_month, quantity, unit, source,
         least(period_month + interval '1 month' + interval '6 days', now())
  from seed_readings;
end $$;

-- 307 West 38th Street is a real building (the hackathon venue, 300,000 sq ft office).
-- Its floor area is real; every reading is invented and the name says so.
do $$
declare
  v_user uuid := '7a1f3c52-9b0e-4d6a-8c21-5e0f4b7d1a90';
  v_id uuid := '11111111-0000-4000-8000-000000000009';
begin
  if exists (select 1 from public.buildings where id = v_id) then
    return;
  end if;

  insert into public.buildings (id, owner_id, name, address, occupancy_group, gross_floor_area_sf, uses_natural_gas)
  values (v_id, v_user, '307 West 38th (sample readings)', '307 West 38th Street, Manhattan, NY 10018', 'B', 300000, true);

  perform setseed(0.38);

  insert into public.meter_readings (building_id, fuel, period_month, quantity, unit, source, created_at)
  select v_id, f.fuel, m::date, 
         round(300000 * f.per_sf
               * (case f.fuel
                    when 'electricity' then (array[.078,.073,.076,.074,.084,.098,.112,.112,.094,.077,.072,.075])[extract(month from m)::int]
                    else (array[.205,.185,.150,.085,.035,.015,.010,.010,.015,.050,.095,.155])[extract(month from m)::int]
                  end)
               * (0.96 + random()::numeric * 0.08), 0),
         f.unit, 'utility_bill', least(m + interval '1 month' + interval '6 days', now())
  from (values ('electricity', 'kWh', 14.0::numeric), ('natural_gas', 'therm', 0.20::numeric)) as f (fuel, unit, per_sf)
  cross join generate_series(date_trunc('month', now()) - interval '24 months',
                             date_trunc('month', now()) - interval '1 month', interval '1 month') as m
  -- One missing summer electricity bill, to show a gap on a building under its limit.
  where not (f.fuel = 'electricity' and m = date_trunc('month', now()) - interval '3 months');
end $$;
