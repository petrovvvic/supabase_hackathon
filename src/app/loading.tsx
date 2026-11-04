import { Block, LoadingBar } from "./skeleton";

export default function Loading() {
  return (
    <>
      <LoadingBar />
      <main className="mx-auto w-full max-w-6xl px-5 py-8" role="status" aria-label="Loading your portfolio">
        <h1 className="text-2xl font-semibold tracking-tight">Portfolio</h1>
        <div className="mt-11 grid gap-3 sm:grid-cols-3">
          <Block className="h-24" />
          <Block className="h-24" />
          <Block className="h-24" />
        </div>
        <Block className="mt-6 h-96" />
      </main>
    </>
  );
}
