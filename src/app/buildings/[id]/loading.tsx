import Link from "next/link";
import { Block, LoadingBar } from "../../skeleton";

export default function Loading() {
  return (
    <>
      <LoadingBar />
      <main className="mx-auto w-full max-w-6xl px-5 py-8" role="status" aria-label="Loading this building">
        <Link href="/" className="text-sm text-muted underline">Portfolio</Link>
        <Block className="mt-2 h-14 w-80 max-w-full" />
        <Block className="mt-6 h-64" />
        <Block className="mt-6 h-44" />
        <div className="mt-6 grid gap-6 md:grid-cols-2">
          <Block className="h-48" />
          <Block className="h-48" />
        </div>
      </main>
    </>
  );
}
