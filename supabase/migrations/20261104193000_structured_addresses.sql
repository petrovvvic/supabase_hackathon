-- Address was free text, so "351 W 44th Street" passed with no borough or ZIP.
-- Store the parts with their own rules, and build the display address from them.
alter table public.buildings
  add column street_address text,
  add column borough text,
  add column zip_code text;

update public.buildings
set street_address = split_part(address, ', ', 1),
    borough = split_part(address, ', ', 2),
    zip_code = right(address, 5)
where address ~ ', (Manhattan|Brooklyn|Queens|Bronx|Staten Island), NY [0-9]{5}$';

-- One building was entered before these rules, with only a street. Hell's Kitchen.
update public.buildings
set street_address = '351 West 44th Street', borough = 'Manhattan', zip_code = '10036'
where address = '351 W 44th Street';

alter table public.buildings
  alter column street_address set not null,
  alter column borough set not null,
  alter column zip_code set not null,
  add constraint buildings_street_address_format
    check (street_address = trim(street_address) and street_address ~ '^[0-9]+(-[0-9]+)?[A-Za-z]? .{2,}' and length(street_address) <= 120),
  add constraint buildings_borough_valid
    check (borough in ('Manhattan', 'Brooklyn', 'Queens', 'Bronx', 'Staten Island')),
  add constraint buildings_zip_code_nyc
    check (zip_code ~ '^1(0[0-4]|1[0-6])[0-9]{2}$');

-- Dropping the old column also drops its unique constraint.
alter table public.buildings drop column address;
alter table public.buildings
  add column address text generated always as (street_address || ', ' || borough || ', NY ' || zip_code) stored;

-- The same building can't be added twice, whatever the capitalization.
create unique index buildings_owner_address_unique
  on public.buildings (owner_id, lower(street_address), zip_code);
