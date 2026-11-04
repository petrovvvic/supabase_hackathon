import Link from "next/link";

// Shown the moment a link is clicked, while the page's data loads.
export function LoadingBar() {
  return (
    <header className="border-b border-line bg-surface">
      <div className="mx-auto flex w-full max-w-6xl items-center px-5 py-3">
        <Link href="/" className="font-semibold tracking-tight">Meterproof</Link>
      </div>
    </header>
  );
}

export function Block({ className }: { className: string }) {
  return <div aria-hidden className={`animate-pulse rounded-lg border border-line bg-surface ${className}`} />;
}
