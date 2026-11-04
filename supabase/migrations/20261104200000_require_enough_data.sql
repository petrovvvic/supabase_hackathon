-- A fine estimate needs real data behind every meter. Overall completeness isn't
-- enough: 12 electricity readings and no gas is 50% complete, yet gas would count
-- as zero, and gas can be most of a building's emissions. So each meter the
-- building uses needs at least 6 of the last 12 months.
-- New columns go last, which is what create or replace view allows.
create or replace view public.building_compliance with (security_invoker = true) as
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
         min(p.reported_months)::int as min_fuel_months,
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
       round(greatest(em.adjusted_tco2e - b.gross_floor_area_sf * l.tco2e_per_sf, 0) * l.penalty_usd_per_tco2e, 0) as adjusted_fine_usd,
       em.min_fuel_months,
       em.min_fuel_months >= 6 as has_enough_data
from public.buildings b
cross join bounds w
join emissions em on em.building_id = b.id
join public.emission_limits l on l.occupancy_group = b.occupancy_group and l.period_start_year = 2024;
