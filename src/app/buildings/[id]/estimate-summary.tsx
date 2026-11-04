import { tons, usd } from "@/lib/format";
import type { Alert, Compliance } from "@/lib/types";

type Tone = "risk" | "warn" | "ok";

// The one sentence a building manager needs, chosen from what the data can support.
function verdict(c: Compliance, alerts: Alert[]): { tone: Tone; title: string; detail: string } {
  const reportedFine = Number(c.reported_fine_usd);
  const adjustedFine = Number(c.adjusted_fine_usd);
  const missing = c.expected_readings - c.reported_readings;
  const missingWords = `${missing} missing ${missing === 1 ? "reading" : "readings"}`;
  const flagged = alerts.filter((a) => a.kind === "out_of_range").length;
  const flaggedWords = flagged === 1 ? "One reading looks wrong" : `${flagged} readings look wrong`;
  const gap = Math.abs(Number(c.adjusted_tco2e) - Number(c.limit_tco2e));

  if (flagged > 0 && adjustedFine > 0) {
    return {
      tone: "warn",
      title: `This ${usd(adjustedFine)} fine may not be real`,
      detail: `${flaggedWords}. Check the flagged ${flagged === 1 ? "reading" : "readings"} before relying on this number.`,
    };
  }
  if (adjustedFine > reportedFine) {
    return {
      tone: "risk",
      title: reportedFine === 0
        ? `Missing data is hiding a ${usd(adjustedFine)} fine`
        : `Missing data could raise the fine to ${usd(adjustedFine)}`,
      detail: `The readings on file show ${usd(reportedFine)}. Add the ${missingWords} to confirm the real number.`,
    };
  }
  if (adjustedFine > 0) {
    return {
      tone: "risk",
      title: `On track for a ${usd(adjustedFine)} fine`,
      detail: `Emissions are ${tons(gap)} over the limit, at $268 per ton.`,
    };
  }
  if (flagged > 0) {
    return {
      tone: "warn",
      title: "No fine expected, but check this data",
      detail: `${flaggedWords}, so this could change once ${flagged === 1 ? "it's" : "they're"} checked.`,
    };
  }
  if (missing > 0) {
    return {
      tone: "warn",
      title: "No fine expected so far",
      detail: `Emissions are ${tons(gap)} under the limit, even with the ${missingWords} estimated.`,
    };
  }
  return {
    tone: "ok",
    title: "No fine expected",
    detail: `Every reading is in, and emissions are ${tons(gap)} under the limit.`,
  };
}

const TITLE_COLOR: Record<Tone, string> = { risk: "text-risk", warn: "text-warn", ok: "text-ok" };

export function EstimateSummary({ compliance: c, alerts }: { compliance: Compliance; alerts: Alert[] }) {
  const { tone, title, detail } = verdict(c, alerts);
  const reported = Number(c.reported_tco2e);
  const adjusted = Number(c.adjusted_tco2e);
  const limit = Number(c.limit_tco2e);
  const estimated = Math.max(adjusted - reported, 0);
  const over = adjusted > limit;
  const scale = Math.max(adjusted, limit) * 1.08;
  const pct = (n: number) => `${(n / scale) * 100}%`;
  const fill = over ? "var(--risk)" : "var(--ok)";
  const stripes = `repeating-linear-gradient(45deg, ${fill} 0 3px, transparent 3px 7px)`;

  return (
    <section className="mt-6 rounded-lg border border-line bg-surface p-5">
      <h2 className={`text-2xl font-semibold tracking-tight ${TITLE_COLOR[tone]}`}>{title}</h2>
      <p className="mt-1 text-muted">{detail}</p>

      <dl className="mt-5 grid gap-4 sm:grid-cols-3">
        <div>
          <dt className="text-sm text-muted">Estimated emissions</dt>
          <dd className="font-mono text-xl font-semibold">{tons(adjusted)}</dd>
        </div>
        <div>
          <dt className="text-sm text-muted">Building&apos;s limit</dt>
          <dd className="font-mono text-xl font-semibold">{tons(limit)}</dd>
        </div>
        <div>
          <dt className="text-sm text-muted">{over ? "Over the limit by" : "Under the limit by"}</dt>
          <dd className={`font-mono text-xl font-semibold ${over ? "text-risk" : "text-ok"}`}>{tons(Math.abs(adjusted - limit))}</dd>
        </div>
      </dl>

      <div
        className="relative mt-5 h-5 overflow-hidden rounded bg-ground"
        role="img"
        aria-label={`${tons(reported)} from readings on file, ${tons(estimated)} estimated for missing months, against a limit of ${tons(limit)}`}
      >
        <div className="absolute inset-y-0 left-0" style={{ width: pct(reported), background: fill }} />
        {estimated > 0 && (
          <div className="absolute inset-y-0" style={{ left: pct(reported), width: pct(estimated), background: stripes }} />
        )}
        <div className="absolute inset-y-0 w-0.5 bg-ink" style={{ left: pct(limit) }} />
      </div>

      <ul className="mt-2 flex flex-wrap gap-x-5 gap-y-1 text-sm text-muted">
        <li className="flex items-center gap-1.5">
          <span aria-hidden className="h-3 w-3 rounded-sm" style={{ background: fill }} />
          From readings on file: {tons(reported)}
        </li>
        {estimated > 0 && (
          <li className="flex items-center gap-1.5">
            <span aria-hidden className="h-3 w-3 rounded-sm" style={{ background: stripes }} />
            Estimated for missing months: {tons(estimated)}
          </li>
        )}
        <li className="flex items-center gap-1.5">
          <span aria-hidden className="h-3 w-0.5 bg-ink" />
          Limit: {tons(limit)}
        </li>
      </ul>

      <details className="mt-4 text-sm text-muted">
        <summary className="cursor-pointer font-medium">How this is calculated</summary>
        <p className="mt-2">
          The fine is $268 for each ton over the limit, using the last 12 completed months. Missing months are filled from the same month last year, or from the average of reported months if last year is missing too.
        </p>
        <p className="mt-2">This is an estimate, not a filing. Local Law 97 is assessed by calendar year.</p>
      </details>
    </section>
  );
}
