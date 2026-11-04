"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("demo@meterproof.app");
  const [password, setPassword] = useState("meterproof-demo");
  const [mode, setMode] = useState<"in" | "up">("in");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setNotice(null);
    const supabase = createClient();
    const { data, error } = mode === "in"
      ? await supabase.auth.signInWithPassword({ email, password })
      : await supabase.auth.signUp({ email, password });
    setBusy(false);
    if (error) return setError(error.message);
    if (!data.session) return setNotice("Check your email to confirm your account, then log in.");
    router.replace("/");
    router.refresh();
  }

  const field = "mt-1 w-full rounded-md border border-line bg-white px-3 py-2 text-base outline-none focus:border-ink";
  return (
    <main className="mx-auto grid min-h-screen w-full max-w-5xl gap-10 px-5 py-12 md:grid-cols-2 md:items-center">
      <section>
        <p className="font-mono text-sm text-muted">Meterproof</p>
        <h1 className="mt-3 text-4xl font-semibold leading-tight tracking-tight">
          Local Law 97 fines are calculated from meter data. Meter data is rarely complete.
        </h1>
        <p className="mt-4 text-lg text-muted">
          See the gaps in your buildings&apos; readings and what they do to your fine estimate, before you file.
        </p>
      </section>
      <form onSubmit={submit} className="rounded-lg border border-line bg-surface p-6">
        <h2 className="text-xl font-semibold">{mode === "in" ? "Log in" : "Create an account"}</h2>
        <label className="mt-5 block text-sm font-medium">
          Email
          <input className={field} type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </label>
        <label className="mt-4 block text-sm font-medium">
          Password
          <input className={field} type="password" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>
        {error && <p role="alert" className="mt-4 rounded-md bg-risk-soft px-3 py-2 text-sm text-risk">{error}</p>}
        {notice && <p className="mt-4 rounded-md bg-ok-soft px-3 py-2 text-sm text-ok">{notice}</p>}
        <button disabled={busy} className="mt-5 w-full rounded-md bg-ink px-4 py-2.5 font-medium text-white disabled:opacity-60">
          {busy ? "One moment…" : mode === "in" ? "Log in" : "Sign up"}
        </button>
        <button
          type="button"
          className="mt-3 w-full text-sm text-muted underline"
          onClick={() => {
            setMode(mode === "in" ? "up" : "in");
            setError(null);
            setNotice(null);
            if (mode === "in") { setEmail(""); setPassword(""); }
          }}
        >
          {mode === "in" ? "Create a new account instead" : "Back to log in"}
        </button>
        <p className="mt-4 text-xs text-muted">The form is filled in with a demo account. All its readings are sample data.</p>
      </form>
    </main>
  );
}
