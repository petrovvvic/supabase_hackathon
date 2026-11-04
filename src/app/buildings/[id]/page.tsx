import { connection } from "next/server";
import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { fuelLabel, monthLabel, usage } from "@/lib/format";
import type { Alert, Building, Compliance, Reading } from "@/lib/types";
import { Header } from "../../header";
import { EstimateSummary } from "./estimate-summary";
import { ReadingForm } from "./reading-form";

const GROUPS: Record<string, string> = { B: "Office", "R-1": "Hotel", "R-2": "Multifamily" };

function windowMonths(start: string) {
  const [y, m] = start.split("-").map(Number);
  return Array.from({ length: 12 }, (_, i) => new Date(Date.UTC(y, m - 1 + i, 1)).toISOString().slice(0, 10));
}

export default async function BuildingPage({ params }: { params: Promise<{ id: string }> }) {
  await connection();
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const supabase = await createClient();
  const [{ data: building, error: buildingError }, { data: compliance, error: complianceError }, { data: alerts, error: alertsError }, { data: readings, error: readingsError }] = await Promise.all([
    supabase.from("buildings").select("id, name, address, occupancy_group, gross_floor_area_sf, uses_natural_gas").eq("id", id).maybeSingle(),
    supabase.from("building_compliance").select("*").eq("building_id", id).maybeSingle(),
    supabase.from("alerts").select("id, building_id, kind, severity, fuel, period_month, message").eq("building_id", id).eq("status", "open").order("severity").order("period_month"),
    supabase.from("meter_readings").select("fuel, period_month, quantity, unit").eq("building_id", id).order("period_month", { ascending: false }).limit(48),
  ]);
  // Failing loudly beats showing a missing reading as a gap when it just didn't load.
  const failed = buildingError ?? complianceError ?? alertsError ?? readingsError;
  if (failed) throw new Error(failed.message);
  if (!building || !compliance) notFound();

  const b = building as Building;
  const c = compliance as Compliance;
  const open = (alerts as Alert[] | null) ?? [];
  const all = (readings as Reading[] | null) ?? [];
  const months = windowMonths(c.window_start);
  const fuels = b.uses_natural_gas ? ["electricity", "natural_gas"] : ["electricity"];
  const flagged = new Set(open.filter((a) => a.kind === "out_of_range").map((a) => `${a.fuel}|${a.period_month}`));
  const has = new Map(all.map((r) => [`${r.fuel}|${r.period_month}`, r]));


  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-6xl px-5 py-8">
        <Link href="/" className="text-sm text-muted underline">Portfolio</Link>
        <h1 className="mt-2 text-2xl font-semibold tracking-tight">{b.name}</h1>
        <p className="text-muted">{b.address} · {GROUPS[b.occupancy_group]} ({b.occupancy_group}) · {b.gross_floor_area_sf.toLocaleString("en-US")} sq ft</p>

        {!c.has_enough_data ? (
        <section className="mt-6 rounded-lg border border-line bg-surface p-5">
          <h2 className="text-lg font-semibold">Not enough data for a fine estimate</h2>
          <p className="mt-1 text-muted">
            Each meter needs at least 6 of the last 12 months. A meter with few readings would make the estimate look lower than it is.
          </p>
          <ul className="mt-3 space-y-1 font-mono text-sm">
            {fuels.map((fuel) => (
              <li key={fuel}>{fuelLabel(fuel)}: {months.filter((m) => has.has(`${fuel}|${m}`)).length} of 12 months</li>
            ))}
          </ul>
        </section>
        ) : (
          <EstimateSummary compliance={c} alerts={open} />
        )}

        <section className="mt-6 rounded-lg border border-line bg-surface p-5">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="text-lg font-semibold">Readings</h2>
            <span className="font-mono text-sm text-muted">{c.reported_readings} of {c.expected_readings} ({c.completeness_pct}%)</span>
          </div>
          <div className="mt-3 overflow-x-auto">
            <table className="w-full min-w-[720px] border-separate border-spacing-1 text-center text-xs">
              <thead>
                <tr>
                  <th className="w-24" />
                  {months.map((m) => <th key={m} className="font-normal text-muted">{monthLabel(m).replace(/ (\d\d)(\d\d)$/, " ’$2")}</th>)}
                </tr>
              </thead>
              <tbody>
                {fuels.map((fuel) => (
                  <tr key={fuel}>
                    <th className="text-left text-sm font-medium">{fuelLabel(fuel)}</th>
                    {months.map((m) => {
                      const r = has.get(`${fuel}|${m}`);
                      const bad = flagged.has(`${fuel}|${m}`);
                      const tone = !r ? "bg-risk-soft text-risk font-semibold" : bad ? "bg-warn-soft text-warn font-semibold" : "bg-ok-soft text-ok";
                      return (
                        <td key={m} className={`rounded px-1 py-2 font-mono ${tone}`}>
                          {r ? usage(Number(r.quantity)) : "gap"}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-2 text-xs text-muted">Electricity in kWh, natural gas in therms. k means thousands.</p>
        </section>

        <div className="mt-6 grid gap-6 md:grid-cols-2">
          <section className="rounded-lg border border-line bg-surface p-5">
            <h2 className="text-lg font-semibold">Open issues ({open.length})</h2>
            {open.length === 0 ? (
              <p className="mt-2 text-sm text-ok">Every month is in and nothing looks off.</p>
            ) : (
              <ul className="mt-3 space-y-2">
                {open.map((a) => (
                  <li key={a.id} className={`rounded-md px-3 py-2 text-sm ${a.severity === "critical" ? "bg-risk-soft" : "bg-warn-soft"}`}>{a.message}</li>
                ))}
              </ul>
            )}
          </section>
          <ReadingForm
            buildingId={b.id}
            months={[...months].reverse()}
            fuels={fuels}
            suggestion={open.find((a) => a.kind === "missing_reading") ?? open.find((a) => a.kind === "out_of_range")}
          />
        </div>
      </main>
    </>
  );
}
