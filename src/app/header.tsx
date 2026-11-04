import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { nextDeadline } from "@/lib/format";

async function signOut() {
  "use server";
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

export function Header() {
  const deadline = nextDeadline();
  return (
    <header className="border-b border-line bg-surface">
      <div className="mx-auto flex w-full max-w-6xl flex-wrap items-center justify-between gap-3 px-5 py-3">
        <Link href="/" className="font-semibold tracking-tight">Meterproof</Link>
        <div className="flex items-center gap-4 text-sm text-muted">
          <span><strong className="font-mono text-ink">{deadline.days}</strong> days to the {deadline.label} filing</span>
          <form action={signOut}><button className="underline">Log out</button></form>
        </div>
      </div>
    </header>
  );
}
