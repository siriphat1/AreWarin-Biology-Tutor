-- BioAre / Manager: Feedback Trash, Restore and Permanent Delete
-- Run in Supabase SQL Editor > New query with the WHOLE FILE selected.
-- Works once the original speaker_feedback + speaker_feedback_admins tables exist.
-- It does not depend on bioare_sessions or the unfinished 10-feature migrations.
-- Non-destructive: existing feedback rows stay active (deleted_at remains NULL).

BEGIN;

ALTER TABLE public.speaker_feedback
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid,
  ADD COLUMN IF NOT EXISTS deleted_reason text;

CREATE INDEX IF NOT EXISTS bioare_feedback_deleted_at_idx
  ON public.speaker_feedback (deleted_at, created_at DESC);

CREATE TABLE IF NOT EXISTS public.bioare_feedback_delete_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  feedback_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('trash','restore','purge')),
  reason text,
  performed_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS bioare_feedback_delete_audit_created_idx
  ON public.bioare_feedback_delete_audit(created_at DESC);

ALTER TABLE public.bioare_feedback_delete_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bioare_feedback_delete_audit FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.bioare_feedback_delete_audit TO authenticated;

-- An independent membership check: works even if other BioAre features
-- are not installed yet. Never trusts a client-supplied user ID.
CREATE OR REPLACE FUNCTION public.bioare_trash_is_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $body$
  SELECT EXISTS (
    SELECT 1 FROM public.speaker_feedback_admins a
    WHERE a.user_id = (SELECT auth.uid())
  );
$body$;
REVOKE ALL ON FUNCTION public.bioare_trash_is_admin() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bioare_trash_is_admin() TO authenticated;

DROP POLICY IF EXISTS bioare_delete_audit_admin_select
  ON public.bioare_feedback_delete_audit;
CREATE POLICY bioare_delete_audit_admin_select
ON public.bioare_feedback_delete_audit
FOR SELECT TO authenticated
USING ((SELECT public.bioare_trash_is_admin()));

-- Soft-delete: remove a response from metrics, but retain it for recovery.
CREATE OR REPLACE FUNCTION public.bioare_trash_feedback(
  p_feedback_id uuid, p_reason text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $body$
DECLARE v_count integer;
BEGIN
  IF auth.uid() IS NULL OR NOT public.bioare_trash_is_admin() THEN
    RAISE EXCEPTION 'BioAre Manager permission required';
  END IF;
  IF p_feedback_id IS NULL THEN RAISE EXCEPTION 'Missing feedback ID'; END IF;
  IF char_length(coalesce(p_reason,'')) > 400 THEN
    RAISE EXCEPTION 'Reason must be at most 400 characters';
  END IF;

  UPDATE public.speaker_feedback
     SET deleted_at=now(), deleted_by=auth.uid(),
         deleted_reason=nullif(btrim(p_reason),'')
   WHERE id=p_feedback_id AND deleted_at IS NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Feedback not found or already in trash';
  END IF;

  -- Immediately unpublish any Feedback Wall excerpt linked to this response.
  IF to_regclass('public.bioare_wall_items') IS NOT NULL THEN
    EXECUTE 'UPDATE public.bioare_wall_items SET is_public = false WHERE feedback_id = $1'
    USING p_feedback_id;
  END IF;

  INSERT INTO public.bioare_feedback_delete_audit(feedback_id,action,reason,performed_by)
  VALUES(p_feedback_id,'trash',nullif(btrim(p_reason),''),auth.uid());
  RETURN true;
END;
$body$;

-- Restore to normal dashboard/exports. Previously published wall excerpts
-- remain unpublished until manually reviewed again.
CREATE OR REPLACE FUNCTION public.bioare_restore_feedback(p_feedback_id uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $body$
DECLARE v_count integer;
BEGIN
  IF auth.uid() IS NULL OR NOT public.bioare_trash_is_admin() THEN
    RAISE EXCEPTION 'BioAre Manager permission required';
  END IF;
  UPDATE public.speaker_feedback
     SET deleted_at=NULL, deleted_by=NULL, deleted_reason=NULL
   WHERE id=p_feedback_id AND deleted_at IS NOT NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN RAISE EXCEPTION 'Trashed feedback not found'; END IF;
  INSERT INTO public.bioare_feedback_delete_audit(feedback_id,action,performed_by)
  VALUES(p_feedback_id,'restore',auth.uid());
  RETURN true;
END;
$body$;

-- Purge one already-trashed response. This cannot be undone.
CREATE OR REPLACE FUNCTION public.bioare_purge_feedback(p_feedback_id uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $body$
DECLARE v_count integer;
BEGIN
  IF auth.uid() IS NULL OR NOT public.bioare_trash_is_admin() THEN
    RAISE EXCEPTION 'BioAre Manager permission required';
  END IF;
  -- Audit first in the same transaction. No PII stored in the audit log.
  IF NOT EXISTS (
    SELECT 1 FROM public.speaker_feedback
    WHERE id=p_feedback_id AND deleted_at IS NOT NULL
  ) THEN RAISE EXCEPTION 'Trashed feedback not found'; END IF;
  INSERT INTO public.bioare_feedback_delete_audit(feedback_id,action,performed_by)
  VALUES(p_feedback_id,'purge',auth.uid());
  DELETE FROM public.speaker_feedback
   WHERE id=p_feedback_id AND deleted_at IS NOT NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN RAISE EXCEPTION 'Unable to delete feedback'; END IF;
  RETURN true;
END;
$body$;

REVOKE ALL ON FUNCTION public.bioare_trash_feedback(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bioare_restore_feedback(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bioare_purge_feedback(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bioare_trash_feedback(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bioare_restore_feedback(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bioare_purge_feedback(uuid) TO authenticated;

COMMIT;

SELECT
 to_regclass('public.speaker_feedback') IS NOT NULL AS feedback_table,
 to_regclass('public.bioare_feedback_delete_audit') IS NOT NULL AS audit_table,
 EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='speaker_feedback' AND column_name='deleted_at') AS trash_column,
 to_regprocedure('public.bioare_trash_feedback(uuid,text)') IS NOT NULL AS trash_function,
 to_regprocedure('public.bioare_restore_feedback(uuid)') IS NOT NULL AS restore_function,
 to_regprocedure('public.bioare_purge_feedback(uuid)') IS NOT NULL AS purge_function;
