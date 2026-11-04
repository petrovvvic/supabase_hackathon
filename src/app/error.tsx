"use client";

export default function Error({ retry }: { error: unknown; retry: () => void }) {
  return (
    <main className="mx-auto w-full max-w-xl px-5 py-16">
      <h1 className="text-2xl font-semibold">We couldn&apos;t load your data</h1>
      <p className="mt-2 text-muted">Nothing has changed. Your readings are safe. Try loading the page again.</p>
      <button onClick={() => retry()} className="mt-5 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white">Try again</button>
    </main>
  );
}
