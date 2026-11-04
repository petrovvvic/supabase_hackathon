// Validates a meter reading before it reaches the database. Uses the caller's
// JWT, so row-level security decides which buildings they can write to.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const UNITS: Record<string, string> = { electricity: "kWh", natural_gas: "therm" };
// Highest believable monthly use per square foot. Matches private.validate_reading().
// Smaller typos pass this and are flagged by the out_of_range alert instead.
const MAX_PER_SF_MONTH: Record<string, number> = { electricity: 20, natural_gas: 1 };

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Use POST." });

  const authorization = req.headers.get("Authorization");
  if (!authorization) return reply(401, { error: "Sign in first." });

  let input: Record<string, unknown>;
  try {
    input = await req.json();
  } catch {
    return reply(400, { error: "Body must be JSON." });
  }
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    return reply(400, { error: "Body must be a JSON object." });
  }

  const { building_id, fuel, period_month, quantity, replace } = input;
  if (typeof building_id !== "string") return reply(400, { error: "building_id is required." });
  if (typeof fuel !== "string" || !UNITS[fuel]) {
    return reply(400, { error: "Fuel must be electricity or natural_gas." });
  }
  if (typeof period_month !== "string" || !/^\d{4}-(0[1-9]|1[0-2])$/.test(period_month)) {
    return reply(400, { error: "Month must look like 2026-03." });
  }
  // Only real numbers and numeric strings: Number() turns false, [] and "  " into 0.
  const isNumeric = typeof quantity === "number" ||
    (typeof quantity === "string" && quantity.trim() !== "");
  const amount = isNumeric ? Number(quantity) : NaN;
  if (!Number.isFinite(amount) || amount < 0) {
    return reply(400, { error: "Usage must be a number that is zero or more." });
  }

  const month = `${period_month}-01`;
  const now = new Date();
  const thisMonth = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}-01`;
  if (month >= thisMonth) return reply(422, { error: "That month hasn't finished yet." });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );

  const { data: building } = await supabase
    .from("buildings")
    .select("id, gross_floor_area_sf, uses_natural_gas")
    .eq("id", building_id)
    .maybeSingle();
  if (!building) return reply(404, { error: "Building not found." });
  if (fuel === "natural_gas" && !building.uses_natural_gas) {
    return reply(422, { error: "This building isn't set up for natural gas." });
  }

  const ceiling = building.gross_floor_area_sf * MAX_PER_SF_MONTH[fuel];
  if (amount > ceiling) {
    return reply(422, {
      error: `${amount.toLocaleString("en-US")} ${UNITS[fuel]} is too high for this building's size. ` +
        `The most we accept for one month is ${ceiling.toLocaleString("en-US")}.`,
    });
  }

  const row = {
    building_id,
    fuel,
    period_month: month,
    quantity: amount,
    unit: UNITS[fuel],
    source: "manual_entry",
  };
  const { error } = replace === true
    ? await supabase.from("meter_readings").upsert(row, { onConflict: "building_id,fuel,period_month" })
    : await supabase.from("meter_readings").insert(row);

  if (error?.code === "23505") {
    return reply(409, { error: "This month already has a reading.", duplicate: true });
  }
  if (error) return reply(400, { error: error.message });
  return reply(200, { ok: true });
});
