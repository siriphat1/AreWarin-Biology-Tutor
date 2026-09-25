/* ============================================================
   Supabase configuration for GitHub Pages
   1) Create a Supabase project
   2) Run supabase/setup.sql
   3) Paste Project URL + anon/publishable key below
   IMPORTANT: Never place the service_role key in GitHub Pages.
   ============================================================ */
window.SCHOOL_APP_CONFIG = {
  SUPABASE_URL: 'https://pcapjltgscofrgfcvdkm.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_NTJJiE0r1hojS-8DTRzWFA_3BPADfEH',
  STORAGE_BUCKET: 'site-media',
  ADMISSION_STORAGE_BUCKET: 'admission-files',
  STUDENT_PORTAL_STORAGE_BUCKET: 'student-portal-files'
};

(() => {
  const cfg = window.SCHOOL_APP_CONFIG;
  const configured = cfg &&
    /^https:\/\/.+\.supabase\.co$/i.test(cfg.SUPABASE_URL || '') &&
    cfg.SUPABASE_ANON_KEY &&
    !cfg.SUPABASE_ANON_KEY.includes('YOUR_');

  if (!configured || !window.supabase?.createClient) {
    window.SCHOOL_SUPABASE = null;
    return;
  }

  window.SCHOOL_SUPABASE = window.supabase.createClient(
    cfg.SUPABASE_URL,
    cfg.SUPABASE_ANON_KEY,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    }
  );
})();
