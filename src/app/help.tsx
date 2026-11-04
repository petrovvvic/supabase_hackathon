// Uses the browser's popover, which handles opening, Esc and clicking outside.
export function Help() {
  return (
    <>
      <button
        popoverTarget="help"
        aria-label="How Meterproof works"
        title="How Meterproof works"
        className="grid h-7 w-7 place-items-center rounded-full border border-line font-semibold text-ink hover:bg-ground"
      >
        ?
      </button>
      <div
        id="help"
        popover="auto"
        className="m-auto w-[min(28rem,calc(100vw-2rem))] rounded-lg border border-line bg-surface p-5 text-ink backdrop:bg-ink/30"
      >
        <h2 className="text-lg font-semibold">How Meterproof works</h2>
        <p className="mt-2 text-muted">
          New York fines big buildings for carbon over their limit. The fine comes from meter readings, so missing or wrong readings make it wrong too.
        </p>
        <ol className="mt-4 list-decimal space-y-2 pl-5">
          <li><strong className="font-semibold">Open a building.</strong></li>
          <li>
            <strong className="font-semibold">Compare the two fines.</strong> Current uses the readings on file. Projected also estimates the missing months.
          </li>
          <li>
            <strong className="font-semibold">Fix the readings.</strong> Red means missing and orange means it looks wrong. Add or correct them, and the fines update.
          </li>
        </ol>
        <p className="mt-4 text-sm text-muted">
          A building needs 6 months of readings per meter to get a fine. These are estimates, not a filing.
        </p>
        <button
          popoverTarget="help"
          popoverTargetAction="hide"
          className="mt-4 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white"
        >
          Got it
        </button>
      </div>
    </>
  );
}
