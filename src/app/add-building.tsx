"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export function AddBuilding() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const f = new FormData(form);
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.from("buildings").insert({
      owner_id: user?.id,
      name: String(f.get("name")).trim(),
      street_address: String(f.get("street_address")).trim().replace(/\s+/g, " "),
      borough: f.get("borough"),
      zip_code: String(f.get("zip_code")).trim(),
      occupancy_group: f.get("occupancy_group"),
      gross_floor_area_sf: Number(f.get("sf")),
      uses_natural_gas: f.get("gas") === "on",
    });
    setBusy(false);
    if (error) {
      return setError(error.code === "23505" ? "You already have a building at this address." :
        error.message.includes("street_address") ? "Enter the street with its building number, like 351 West 44th Street." :
        error.message.includes("zip_code") ? "Enter a New York City ZIP code." :
        error.code === "23514" ? "Check the details. LL97 generally covers buildings over 25,000 sq ft." : error.message);
    }
    form.reset();
    setOpen(false);
    router.refresh();
  }

  const field = "mt-1 w-full rounded-md border border-line bg-white px-3 py-2 outline-none focus:border-ink";
  if (!open) {
    return <button onClick={() => setOpen(true)} className="mt-5 rounded-md border border-line bg-surface px-4 py-2 text-sm font-medium">Add a building</button>;
  }
  return (
    <form onSubmit={submit} className="mt-5 grid gap-4 rounded-lg border border-line bg-surface p-5 sm:grid-cols-2">
      <label className="text-sm font-medium">Name<input name="name" required maxLength={120} className={field} /></label>
      <label className="text-sm font-medium">Street address
        <input name="street_address" required maxLength={120} pattern="\s*[0-9]+(-[0-9]+)?[A-Za-z]? .{2,}" title="Building number and street, like 351 West 44th Street" placeholder="351 West 44th Street" autoComplete="address-line1" className={field} />
      </label>
      <div className="grid grid-cols-2 gap-4">
        <label className="text-sm font-medium">Borough
          <select name="borough" required defaultValue="" className={field}>
            <option value="" disabled>Select</option>
            <option>Manhattan</option>
            <option>Brooklyn</option>
            <option>Queens</option>
            <option>Bronx</option>
            <option>Staten Island</option>
          </select>
        </label>
        <label className="text-sm font-medium">ZIP code
          <input name="zip_code" required inputMode="numeric" maxLength={5} pattern="1(0[0-4]|1[0-6])[0-9]{2}" title="A New York City ZIP code, like 10036" placeholder="10036" autoComplete="postal-code" className={field} />
        </label>
      </div>
      <label className="text-sm font-medium">Building type
        <select name="occupancy_group" className={field} defaultValue="R-2">
          <option value="R-2">Multifamily (R-2)</option>
          <option value="B">Office (B)</option>
          <option value="R-1">Hotel (R-1)</option>
        </select>
      </label>
      <label className="text-sm font-medium">Gross floor area (sq ft)<input name="sf" type="number" min={25001} required className={field} /></label>
      <label className="flex items-center gap-2 text-sm font-medium sm:col-span-2"><input name="gas" type="checkbox" defaultChecked /> Uses natural gas</label>
      {error && <p role="alert" className="rounded-md bg-risk-soft px-3 py-2 text-sm text-risk sm:col-span-2">{error}</p>}
      <div className="flex gap-2 sm:col-span-2">
        <button disabled={busy} className="rounded-md bg-ink px-4 py-2 text-sm font-medium text-white disabled:opacity-60">{busy ? "Saving…" : "Save building"}</button>
        <button type="button" onClick={() => setOpen(false)} className="rounded-md border border-line px-4 py-2 text-sm">Cancel</button>
      </div>
    </form>
  );
}
