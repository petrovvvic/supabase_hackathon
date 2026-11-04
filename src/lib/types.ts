export type Compliance = {
  building_id: string;
  window_start: string;
  window_end: string;
  reported_readings: number;
  expected_readings: number;
  completeness_pct: number;
  reported_tco2e: number;
  adjusted_tco2e: number;
  limit_tco2e: number;
  reported_fine_usd: number;
  adjusted_fine_usd: number;
};
export type Building = {
  id: string;
  name: string;
  address: string;
  occupancy_group: string;
  gross_floor_area_sf: number;
  uses_natural_gas: boolean;
};
export type Alert = {
  id: string;
  building_id: string;
  kind: "missing_reading" | "stale_data" | "out_of_range";
  severity: "warning" | "critical";
  fuel: string;
  period_month: string;
  message: string;
};
export type Reading = { fuel: string; period_month: string; quantity: number; unit: string };
