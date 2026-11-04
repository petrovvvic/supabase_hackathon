"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { fuelLabel, monthLabel } from "@/lib/format";
import type { Alert } from "@/lib/types";

export function ReadingForm({ buildingId, months, fuels, suggestion }: {
  buildingId: string; months: string[]; fuels: string[]; suggestion?: Alert;
}) {
  const router = useRouter();
  const [fuel, setFuel] = useState(suggestion?.fuel ?? fuels[0]);
  const [month, setMonth] = useState(suggestion?.period_month ?? months[0]);
  const [quantity, setQuantity] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);
  const [duplicate, setDuplicate] = useState(false);
  const [busy, setBusy] = useState(false);

  // After a save, point the form at the next open gap.
  const [suggestedId, setSuggestedId] = useState(suggestion?.id);
  if (suggestion?.id !== suggestedId) {
    setSuggestedId(suggestion?.id);
    if (suggestion) { setFuel(suggestion.fuel); setMonth(suggestion.period_month); }
  }

  // The form is already on a flagged reading, so saving means correcting it.
  const correcting = suggestion?.kind === "out_of_range" && fuel === suggestion.fuel && month === suggestion.period_month;

  async function send(replace: boolean) {
    setBusy(true);
    setError(null);
    setSaved(null);
    setDuplicate(false);
    const { data, error } = await createClient().functions.invoke("submit-reading", {
      body: { building_id: buildingId, fuel, period_month: month.slice(0, 7), quantity, replace },
    });
    setBusy(false);
    if (error) {
      const body = await (error as { context?: Response }).context?.json?.().catch(() => null);
      setDuplicate(Boolean(body?.duplicate));
      return setError(body?.error ?? "That reading couldn't be saved. Try again.");
    }
    if (data?.ok) {
      setSaved(`${fuelLabel(fuel)} for ${monthLabel(month, "long")} saved.`);
      setQuantity("");
      router.refresh();
    }
  }

  const field = "mt-1 w-full rounded-md border border-line bg-white px-3 py-2 outline-none focus:border-ink";
  const unit = fuel === "natural_gas" ? "therms" : "kWh";
  return (
    <form onSubmit={(e) => { e.preventDefault(); send(correcting); }} className="rounded-lg border border-line bg-surface p-5">
      <h2 className="text-lg font-semibold">{correcting ? "Correct this reading" : "Add a reading"}</h2>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <label className="text-sm font-medium">Meter
          <select className={field} value={fuel} onChange={(e) => setFuel(e.target.value)}>
            {fuels.map((f) => <option key={f} value={f}>{fuelLabel(f)}</option>)}
          </select>
        </label>
        <label className="text-sm font-medium">Month
          <select className={field} value={month} onChange={(e) => setMonth(e.target.value)}>
            {months.map((m) => <option key={m} value={m}>{monthLabel(m, "long")}</option>)}
          </select>
        </label>
      </div>
      <label className="mt-3 block text-sm font-medium">Usage ({unit})
        <input className={field} inputMode="decimal" required value={quantity} onChange={(e) => setQuantity(e.target.value)} />
      </label>
      {error && <p role="alert" className="mt-3 rounded-md bg-risk-soft px-3 py-2 text-sm text-risk">{error}</p>}
      {saved && <p className="mt-3 rounded-md bg-ok-soft px-3 py-2 text-sm text-ok">{saved}</p>}
      <div className="mt-4 flex flex-wrap gap-2">
        <button disabled={busy} className="rounded-md bg-ink px-4 py-2 text-sm font-medium text-white disabled:opacity-60">{busy ? "Checking…" : correcting ? "Replace reading" : "Save reading"}</button>
        {duplicate && <button type="button" disabled={busy} onClick={() => send(true)} className="rounded-md border border-line px-4 py-2 text-sm font-medium">Replace the existing reading</button>}
      </div>
    </form>
  );
}
