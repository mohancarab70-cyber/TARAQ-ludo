import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json({
    urlConfigured: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()),
    anonKeyConfigured: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim())
  }, { headers: { "Cache-Control": "no-store" } });
}
