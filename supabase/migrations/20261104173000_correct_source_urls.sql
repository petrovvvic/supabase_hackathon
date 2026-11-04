-- Point reference data at the sources the values were actually checked against.
update public.emission_factors
set source_url = 'https://thorntontomasetti.com/local-law-97';

update public.emission_limits
set source_url = case occupancy_group
  when 'B' then 'https://www.ny-engineers.com/blog/local-law-97-of-2019'
  else 'https://withum.com/resources/planning-for-new-york-citys-carbon-tax-local-law-97-explained'
end;
