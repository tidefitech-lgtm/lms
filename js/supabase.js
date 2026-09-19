// =========================================================
// TIDEF ITECH LMS — Supabase Initialization
// =========================================================
// 1. Create a project at https://supabase.com/dashboard
// 2. Project Settings → API → copy "Project URL" and "anon public" key.
// 3. Paste them below.
// 4. Run supabase/migrations/0001_init.sql in the SQL Editor (creates
//    tables, triggers, RLS policies, and the profile-photos bucket).
// 5. See README.md in the project root for full setup steps.
// =========================================================

import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

// TODO: replace with your real project values
const SUPABASE_URL = "https://urqdhvabisnpzmsloeie.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_q5dLfmf79cs-AayZd9qe0A_ICsIE846";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
