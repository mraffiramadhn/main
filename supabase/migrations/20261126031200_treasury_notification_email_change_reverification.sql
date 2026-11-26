-- Require email changes to be re-verified in a separate save, preventing one-step bypass.
create or replace function public.treasury_admin_save_notification_contact(
 p_student_id text,p_student_name text,p_email text,p_consented boolean,p_verified boolean,p_active boolean default true
) returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_role text; v_old_email text; v_verified_at timestamptz; v_consented_at timestamptz; v_email text:=lower(trim(coalesce(p_email,'')));
begin
 if not public.treasury_session_valid() then raise exception 'Treasury session invalid/expired'; end if;
 select role into v_role from public.treasury_roles where user_id=auth.uid();
 if v_role not in ('admin','superadmin') or not exists(select 1 from public.treasury_editors where user_id=auth.uid()) then raise exception 'Admin/editor access required'; end if;
 if not exists(select 1 from public.treasury_state ts cross join lateral jsonb_array_elements(coalesce(ts.payload->'students','[]'::jsonb)) s where ts.id=true and s->>'id'=p_student_id) then raise exception 'Student not found in current Treasury roster'; end if;
 if v_email='' or v_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then raise exception 'Valid email required'; end if;
 select email into v_old_email from public.treasury_notification_contacts where student_id=p_student_id;
 if v_old_email is distinct from v_email then
  v_verified_at:=null;
  v_consented_at:=case when p_consented then now() else null end;
 else
  v_verified_at:=case when p_verified then coalesce((select verified_at from public.treasury_notification_contacts where student_id=p_student_id),now()) else null end;
  v_consented_at:=case when p_consented then coalesce((select consented_at from public.treasury_notification_contacts where student_id=p_student_id),now()) else null end;
 end if;
 insert into public.treasury_notification_contacts(student_id,student_name,email,consented_at,verified_at,active,updated_at)
 values(p_student_id,p_student_name,v_email,v_consented_at,v_verified_at,p_active)
 on conflict(student_id) do update set student_name=excluded.student_name,email=excluded.email,consented_at=excluded.consented_at,verified_at=excluded.verified_at,active=excluded.active,updated_at=now();
 insert into public.treasury_audit_log(actor_id,actor_email,actor_role,action,details)
 values(auth.uid(),coalesce(auth.jwt()->>'email',''),v_role,'notification_contact_updated',jsonb_build_object('student_id',p_student_id,'student_name',p_student_name,'email',v_email,'consented',p_consented,'verified',v_verified_at is not null,'active',p_active,'email_changed',v_old_email is distinct from v_email));
 return jsonb_build_object('ok',true,'email_changed',v_old_email is distinct from v_email,'verified',v_verified_at is not null,'consented',v_consented_at is not null,'active',p_active);
end $$;
revoke all on function public.treasury_admin_save_notification_contact(text,text,text,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function public.treasury_admin_save_notification_contact(text,text,text,boolean,boolean,boolean) to authenticated;
