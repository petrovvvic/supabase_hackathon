import { connection } from "next/server";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { monthLabel, tons, usd } from "@/lib/format";
import type { Alert, Building, Compliance } from "@/lib/types";
import { Header } from "./header";
import { AddBuilding } from "./add-building";

// Signed-in data only: render per request instead of prerendering a shell.
export const instant = false;

export default async function Portfolio() {
  await connection();
  const supabase = await createClient();
  const [{ data: buildings, error }, { data: compliance }, { data: alerts }] = await Promise.all([
    supabase.from("buildings").select("id, name, address, occupancy_group, gross_floor_area_sf, uses_natural_gas").order("name"),
    supabase.from("building_compliance").select("*"),
    supabase.from("alerts").select("id, building_id, kind, severity, fuel, period_month, message").eq("status", "open"),
  ]);
  if (error) throw new Error(error.message);

  const byId = new Map((compliance as Compliance[] | null ?? []).map((c) => [c.building_id, c]));
  const open = (alerts as Alert[] | null) ?? [];
  const rows = ((buildings as Building[] | null) ?? []).map((b) => ({
    b, c: byId.get(b.id), issues: open.filter((a) => a.building_id === b.id).length,
  }));
  // Buildings whose estimate moves once the gaps are filled matter most.
  rows.sort((x, y) =>
    Math.abs((y.c?.adjusted_fine_usd ?? 0) - (y.c?.reported_fine_usd ?? 0)) -
    Math.abs((x.c?.adjusted_fine_usd ?? 0) - (x.c?.reported_fine_usd ?? 0)) || y.issues - x.issues);

  const reported = rows.reduce((s, r) => s + Number(r.c?.reported_fine_usd ?? 0), 0);
  const adjusted = rows.reduce((s, r) => s + Number(r.c?.adjusted_fine_usd ?? 0), 0);
  const window = rows[0]?.c;

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-6xl px-5 py-8">
        {rows.length === 0 ? (
          <section className="rounded-lg border border-line bg-surface p-8">
            <h1 className="text-2xl font-semibold">Add your first building</h1>
            <p className="mt-2 text-muted">Once it has readings, you&apos;ll see its emissions estimate and any gaps here.</p>
          </section>
        ) : (
          <>
            <h1 className="text-2xl font-semibold tracking-tight">Portfolio</h1>
            {window && (
              <p className="mt-1 text-muted">
                Estimates for {monthLabel(window.window_start)} to {monthLabel(window.window_end)}, using 2024–2029 limits. Not a filing.
              </p>
            )}
            <div className="mt-5 grid gap-3 sm:grid-cols-3">
              <Stat label="Fine estimate from reported data" value={usd(reported)} />
              <Stat label="Fine estimate with gaps filled" value={usd(adjusted)} tone={adjusted > reported ? "risk" : undefined} />
              <Stat label="Open data issues" value={String(open.length)} tone={open.length ? "warn" : undefined} />
            </div>
            <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
              <table className="w-full min-w-[720px] text-left text-sm">
                <thead className="border-b border-line text-muted">
                  <tr>
                    <th className="px-4 py-3 font-medium">Building</th>
                    <th className="px-4 py-3 font-medium">Data complete</th>
                    <th className="px-4 py-3 text-right font-medium">Emissions / limit</th>
                    <th className="px-4 py-3 text-right font-medium">Reported fine</th>
                    <th className="px-4 py-3 text-right font-medium">With gaps filled</th>
                    <th className="px-4 py-3 text-right font-medium">Issues</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map(({ b, c, issues }) => (
                    <tr key={b.id} className="border-b border-line last:border-0 hover:bg-ground">
                      <td className="px-4 py-3">
                        <Link href={`/buildings/${b.id}`} className="font-medium underline-offset-2 hover:underline">{b.name}</Link>
                        <div className="text-xs text-muted">{b.address}</div>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <div className="h-1.5 w-20 rounded-full bg-line">
                            <div className={`h-1.5 rounded-full ${Number(c?.completeness_pct) === 100 ? "bg-ok" : "bg-risk"}`} style={{ width: `${c?.completeness_pct ?? 0}%` }} />
                          </div>
                          <span className="font-mono text-xs">{c?.reported_readings}/{c?.expected_readings}</span>
                        </div>
                      </td>
                      <td className="px-4 py-3 text-right font-mono">{c && `${tons(c.adjusted_tco2e)} / ${tons(c.limit_tco2e)}`}</td>
                      <td className="px-4 py-3 text-right font-mono">{usd(Number(c?.reported_fine_usd ?? 0))}</td>
                      <td className={`px-4 py-3 text-right font-mono ${Number(c?.adjusted_fine_usd) > Number(c?.reported_fine_usd) ? "font-semibold text-risk" : ""}`}>{usd(Number(c?.adjusted_fine_usd ?? 0))}</td>
                      <td className="px-4 py-3 text-right font-mono">{issues}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
        <AddBuilding />
      </main>
    </>
  );
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: "risk" | "warn" }) {
  const color = tone === "risk" ? "text-risk" : tone === "warn" ? "text-warn" : "";
  return (
    <div className="rounded-lg border border-line bg-surface p-4">
      <div className="text-sm text-muted">{label}</div>
      <div className={`mt-1 font-mono text-2xl font-semibold ${color}`}>{value}</div>
    </div>
  );
}
