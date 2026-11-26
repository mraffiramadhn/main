-- Treasury Email Admin Panel v1: private contact management + manual invoice queue
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
  v_verified_at:=case when p_verified then now() else null end; v_consented_at:=case when p_consented then now() else null end;
 else
  v_verified_at:=case when p_verified then coalesce((select verified_at from public.treasury_notification_contacts where student_id=p_student_id),now()) else null end;
  v_consented_at:=case when p_consented then coalesce((select consented_at from public.treasury_notification_contacts where student_id=p_student_id),now()) else null end;
 end if;
 insert into public.treasury_notification_contacts(student_id,student_name,email,consented_at,verified_at,active,updated_at)
 values(p_student_id,p_student_name,v_email,v_consented_at,v_verified_at,p_active)
 on conflict(student_id) do update set student_name=excluded.student_name,email=excluded.email,consented_at=excluded.consented_at,verified_at=excluded.verified_at,active=excluded.active,updated_at=now();
 insert into public.treasury_audit_log(actor_id,actor_email,actor_role,action,details)
 values(auth.uid(),coalesce(auth.jwt()->>'email',''),v_role,'notification_contact_updated',jsonb_build_object('student_id',p_student_id,'student_name',p_student_name,'email',v_email,'consented',p_consented,'verified',p_verified,'active',p_active,'email_changed',v_old_email is distinct from v_email));
 return jsonb_build_object('ok',true,'email_changed',v_old_email is distinct from v_email,'verified',v_verified_at is not null,'consented',v_consented_at is not null,'active',p_active);
end $$;
revoke all on function public.treasury_admin_save_notification_contact(text,text,text,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function public.treasury_admin_save_notification_contact(text,text,text,boolean,boolean,boolean) to authenticated;

create or replace function public.treasury_admin_queue_invoice(p_student_id text)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_role text; v_today date:=(now() at time zone 'Asia/Jakarta')::date; v_student jsonb; v_student_name text; v_email text;
 v_current_week jsonb; v_current_label text; v_start date; v_week_id text; v_weekly numeric; v_manual numeric; v_current_due numeric:=0; v_arrears numeric:=0; v_arrears_periods jsonb:='[]'::jsonb; v_total numeric; v_payload jsonb; v_queue_id uuid;
begin
 if not public.treasury_session_valid() then raise exception 'Treasury session invalid/expired'; end if;
 select role into v_role from public.treasury_roles where user_id=auth.uid();
 if v_role not in ('admin','superadmin') or not exists(select 1 from public.treasury_editors where user_id=auth.uid()) then raise exception 'Admin/editor access required'; end if;
 select s into v_student from public.treasury_state ts cross join lateral jsonb_array_elements(coalesce(ts.payload->'students','[]'::jsonb)) s where ts.id=true and s->>'id'=p_student_id;
 if v_student is null then raise exception 'Student not found'; end if;
 v_student_name:=v_student->>'name';
 select email into v_email from public.treasury_notification_contacts where student_id=p_student_id and active and consented_at is not null and verified_at is not null;
 if v_email is null then raise exception 'Email must be active, consented and manually verified before queueing'; end if;
 select w->>'id',w->>'label',c.start_date into v_week_id,v_current_label,v_start from public.treasury_state ts
 cross join lateral jsonb_array_elements(coalesce(ts.payload->'weeks','[]'::jsonb)) w
 join (values ('September - 3',date '2026-09-14'),('September - 4',date '2026-09-21'),('September - 5',date '2026-09-28'),('October - 1',date '2026-10-05'),('October - 2',date '2026-10-12'),('October - 3',date '2026-10-19'),('November - 1',date '2026-11-02'),('November - 2',date '2026-11-09'),('November - 3',date '2026-11-16'),('November - 4',date '2026-11-23'),('December - 1',date '2026-11-30'),('December - 2',date '2026-12-07'),('December - 3',date '2026-12-14'),('January - 1',date '2027-01-04')) c(label,start_date)
 on lower(regexp_replace(trim(w->>'label'),'[[:space:]]*-[[:space:]]*',' - ','g'))=lower(c.label) where ts.id=true and c.start_date<=v_today order by c.start_date desc limit 1;
 if v_week_id is null then raise exception 'No current billable week found'; end if;
 v_weekly:=greatest(5000,coalesce(nullif(v_student->>'weeklyAmount','')::numeric,5000)); v_manual:=coalesce(nullif(v_student->>'manualOwed','')::numeric,0);
 select greatest(0,v_weekly-case when v_student->'paid'->v_week_id='true'::jsonb then v_weekly when v_student->'paid'->v_week_id='false'::jsonb then 0 else greatest(0,coalesce(nullif(v_student->'paid'->>v_week_id,'')::numeric,0)) end) into v_current_due;
 with week_data as(select w->>'id' week_id,w->>'label' label,c.start_date,greatest(0,v_weekly-case when v_student->'paid'->(w->>'id')='true'::jsonb then v_weekly when v_student->'paid'->(w->>'id')='false'::jsonb then 0 else greatest(0,coalesce(nullif(v_student->'paid'->>(w->>'id'),'')::numeric,0)) end) outstanding
 from public.treasury_state ts cross join lateral jsonb_array_elements(coalesce(ts.payload->'weeks','[]'::jsonb)) w join (values ('September - 3',date '2026-09-14'),('September - 4',date '2026-09-21'),('September - 5',date '2026-09-28'),('October - 1',date '2026-10-05'),('October - 2',date '2026-10-12'),('October - 3',date '2026-10-19'),('November - 1',date '2026-11-02'),('November - 2',date '2026-11-09'),('November - 3',date '2026-11-16'),('November - 4',date '2026-11-23'),('December - 1',date '2026-11-30'),('December - 2',date '2026-12-07'),('December - 3',date '2026-12-14'),('January - 1',date '2027-01-04')) c(label,start_date) on lower(regexp_replace(trim(w->>'label'),'[[:space:]]*-[[:space:]]*',' - ','g'))=lower(c.label) where ts.id=true and c.start_date<=v_today and c.start_date<v_start)
 select coalesce(sum(outstanding),0),coalesce(jsonb_agg(jsonb_build_object('period',label,'outstanding',outstanding,'due_date',start_date+4) order by start_date) filter(where outstanding>0),'[]'::jsonb) into v_arrears,v_arrears_periods from week_data;
 v_arrears:=v_arrears+v_manual; v_total:=v_arrears+v_current_due; if v_total<=0 then return jsonb_build_object('ok',false,'reason','Student has no outstanding balance'); end if;
 v_payload:=jsonb_build_object('current_period',v_current_label,'current_due',v_current_due,'arrears',v_arrears,'total_due',v_total,'arrears_periods',v_arrears_periods,'deadline',v_start+4,'timezone','Asia/Jakarta','manual_queue',true);
 insert into public.treasury_notification_queue(automation_key,dedupe_key,student_id,student_name,recipient_email,subject,payload,scheduled_at)
 values('weekly_invoice_manual','manual-invoice:'||v_current_label||':'||p_student_id||':'||gen_random_uuid()::text,p_student_id,v_student_name,v_email,'[Treasury X1] Tagihan Kas — '||v_current_label,v_payload,now()) returning id into v_queue_id;
 insert into public.treasury_audit_log(actor_id,actor_email,actor_role,action,details) values(auth.uid(),coalesce(auth.jwt()->>'email',''),v_role,'invoice_manual_queued',jsonb_build_object('student_id',p_student_id,'period',v_current_label,'queue_id',v_queue_id,'total_due',v_total,'email',v_email));
 return jsonb_build_object('ok',true,'queue_id',v_queue_id,'student_name',v_student_name,'period',v_current_label,'total_due',v_total,'email',v_email,'delivery_status','queued_not_sent');
end $$;
revoke all on function public.treasury_admin_queue_invoice(text) from public,anon,authenticated;
grant execute on function public.treasury_admin_queue_invoice(text) to authenticated;
