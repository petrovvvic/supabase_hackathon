export const usd = (n: number) =>
  n.toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
export const tons = (n: number) =>
  `${Number(n).toLocaleString("en-US", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} t`;
// Grid cells: small gas bills stay exact instead of turning into 0.2k.
export const usage = (n: number) =>
  n < 1000 ? String(Math.round(n)) : `${Math.round(n / 100) / 10}k`;
export const monthLabel = (iso: string, style: "short" | "long" = "short") =>
  new Date(`${iso}T00:00:00Z`).toLocaleDateString("en-US", {
    month: style, year: "numeric", timeZone: "UTC",
  });
export const fuelLabel = (fuel: string) => (fuel === "natural_gas" ? "Natural gas" : "Electricity");

// Annual LL97 reports fall due on May 1. Buildings with special status can differ.
export function nextDeadline(now = new Date()) {
  const year = now.getUTCMonth() > 4 || (now.getUTCMonth() === 4 && now.getUTCDate() > 1)
    ? now.getUTCFullYear() + 1 : now.getUTCFullYear();
  const date = new Date(Date.UTC(year, 4, 1));
  const days = Math.ceil((date.getTime() - now.getTime()) / 86_400_000);
  return { label: `May 1, ${year}`, days };
}
