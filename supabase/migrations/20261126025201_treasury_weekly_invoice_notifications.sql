-- Treasury Email Automation v1: weekly invoice queue (no email sending yet)
create table if not exists public.treasury_notification_contacts (
  student_id text primary key,
  student_name text not null,
  email text not null check (email = lower(trim(email)) and email like '%@%'),
  consented_at timestamptz,
  verified_at timestamptz,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
create table if not exists public.treasury_notification_queue (
  id uuid primary key default gen_random_uuid(), automation_key text not null, dedupe_key text not null unique,
  student_id text not null, student_name text not null, recipient_email text not null, subject text not null,
  payload jsonb not null default '{}'::jsonb, scheduled_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending','sent','failed','skipped')),
  sent_at timestamptz, attempts integer not null default 0, last_error text, created_at timestamptz not null default now()
);
create table if not exists public.treasury_notification_runs (
  id bigint generated always as identity primary key, automation_key text not null, started_at timestamptz not null default now(),
  finished_at timestamptz, due_students integer not null default 0, queued_count integer not null default 0,
  skipped_no_contact integer not null default 0, result jsonb not null default '{}'::jsonb
);
alter table public.treasury_notification_contacts enable row level security;
alter table public.treasury_notification_queue enable row level security;
alter table public.treasury_notification_runs enable row level security;
drop policy if exists treasury_contacts_admin_read on public.treasury_notification_contacts;
create policy treasury_contacts_admin_read on public.treasury_notification_contacts for select to authenticated
using (treasury_session_valid() and exists(select 1 from public.treasury_roles r where r.user_id=(select auth.uid()) and r.role in ('admin','superadmin')));
drop policy if exists treasury_contacts_admin_write on public.treasury_notification_contacts;
create policy treasury_contacts_admin_write on public.treasury_notification_contacts for all to authenticated
using (treasury_session_valid() and exists(select 1 from public.treasury_roles r where r.user_id=(select auth.uid()) and r.role in ('admin','superadmin')))
with check (treasury_session_valid() and exists(select 1 from public.treasury_roles r where r.user_id=(select auth.uid()) and r.role in ('admin','superadmin')));
drop policy if exists treasury_notification_queue_admin_read on public.treasury_notification_queue;
create policy treasury_notification_queue_admin_read on public.treasury_notification_queue for select to authenticated
using (treasury_session_valid() and exists(select 1 from public.treasury_roles r where r.user_id=(select auth.uid()) and r.role in ('admin','superadmin')));
drop policy if exists treasury_notification_runs_admin_read on public.treasury_notification_runs;
create policy treasury_notification_runs_admin_read on public.treasury_notification_runs for select to authenticated
using (treasury_session_valid() and exists(select 1 from public.treasury_roles r where r.user_id=(select auth.uid()) and r.role in ('admin','superadmin')));
revoke all on public.treasury_notification_contacts from anon,authenticated;
revoke all on public.treasury_notification_queue from anon,authenticated;
revoke all on public.treasury_notification_runs from anon,authenticated;
grant select,insert,update,delete on public.treasury_notification_contacts to authenticated;
grant select on public.treasury_notification_queue,public.treasury_notification_runs to authenticated;

create or replace function public.treasury_enqueue_weekly_invoice_notifications()
returns jsonb language plpgsql security invoker set search_path=public,pg_catalog as $$
declare
 v_today date := (now() at time zone 'Asia/Jakarta')::date;
 v_run_id bigint; v_current_label text; v_due_count integer:=0; v_queued integer:=0; v_missing integer:=0;
begin
 insert into public.treasury_notification_runs(automation_key) values('weekly_invoice_monday') returning id into v_run_id;
 with calendar(label,start_date) as (values
  ('September - 3',date '2026-09-14'),('September - 4',date '2026-09-21'),('September - 5',date '2026-09-28'),
  ('October - 1',date '2026-10-05'),('October - 2',date '2026-10-12'),('October - 3',date '2026-10-19'),
  ('November - 1',date '2026-11-02'),('November - 2',date '2026-11-09'),('November - 3',date '2026-11-16'),('November - 4',date '2026-11-23'),
  ('December - 1',date '2026-11-30'),('December - 2',date '2026-12-07'),('December - 3',date '2026-12-14'),('January - 1',date '2027-01-04')),
 weeks as (
  select w->>'id' week_id,w->>'label' label,c.start_date from public.treasury_state ts
  cross join lateral jsonb_array_elements(coalesce(ts.payload->'weeks','[]'::jsonb)) w
  join calendar c on lower(regexp_replace(trim(w->>'label'),'[[:space:]]*-[[:space:]]*',' - ','g'))=lower(c.label)
  where ts.id=true and c.start_date<=v_today
 ),
 current_week as(select label,start_date from weeks order by start_date desc limit 1),
 students as(select s student,s->>'id' student_id,s->>'name' student_name,
  greatest(5000,coalesce(nullif(s->>'weeklyAmount','')::numeric,5000)) weekly_amount,
  coalesce(nullif(s->>'manualOwed','')::numeric,0) manual_owed
  from public.treasury_state ts cross join lateral jsonb_array_elements(coalesce(ts.payload->'students','[]'::jsonb)) s where ts.id=true),
 paid_by_week as(select st.student_id,st.student_name,st.student,st.weekly_amount,st.manual_owed,w.week_id,w.label,w.start_date,
  case when st.student->'paid'->w.week_id='true'::jsonb then st.weekly_amount
       when st.student->'paid'->w.week_id='false'::jsonb then 0
       else greatest(0,coalesce(nullif(st.student->'paid'->>w.week_id,'')::numeric,0)) end paid_amount
  from students st join weeks w on true),
 obligations as(select p.student_id,p.student_name,p.manual_owed,cw.label current_label,cw.start_date current_start,
  coalesce(sum(greatest(0,p.weekly_amount-p.paid_amount)) filter(where p.start_date<cw.start_date),0)+p.manual_owed arrears,
  coalesce(sum(greatest(0,p.weekly_amount-p.paid_amount)) filter(where p.start_date=cw.start_date),0) current_due,
  coalesce(jsonb_agg(jsonb_build_object('period',p.label,'outstanding',greatest(0,p.weekly_amount-p.paid_amount),'due_date',p.start_date+4)
   order by p.start_date) filter(where p.start_date<cw.start_date and greatest(0,p.weekly_amount-p.paid_amount)>0),'[]'::jsonb) arrears_periods
  from paid_by_week p cross join current_week cw
  group by p.student_id,p.student_name,p.student,p.weekly_amount,p.manual_owed,cw.label,cw.start_date),
 due as(select o.*,coalesce(c.email,'') email,o.arrears+o.current_due total_due from obligations o
  left join public.treasury_notification_contacts c on c.student_id=o.student_id and c.active=true and c.consented_at is not null and c.verified_at is not null
  where o.arrears+o.current_due>0),
 inserted as(insert into public.treasury_notification_queue(automation_key,dedupe_key,student_id,student_name,recipient_email,subject,payload,scheduled_at)
  select 'weekly_invoice_monday','weekly-invoice:'||current_label||':'||student_id,student_id,student_name,email,
   '[Treasury X1] Tagihan Kas — '||current_label,
   jsonb_build_object('current_period',current_label,'current_due',current_due,'arrears',arrears,'total_due',total_due,
    'arrears_periods',arrears_periods,'deadline',current_start+4,'timezone','Asia/Jakarta'),now()
  from due where email<>'' on conflict(dedupe_key) do nothing returning id)
 select (select count(*) from due),(select count(*) from inserted),(select count(*) from due where email=''),(select label from current_week)
 into v_due_count,v_queued,v_missing,v_current_label;
 update public.treasury_notification_runs set finished_at=now(),due_students=v_due_count,queued_count=v_queued,skipped_no_contact=v_missing,
  result=jsonb_build_object('billing_date',v_today,'current_period',v_current_label,'timezone','Asia/Jakarta') where id=v_run_id;
 return jsonb_build_object('run_id',v_run_id,'billing_date',v_today,'current_period',v_current_label,'due_students',v_due_count,'queued',v_queued,'skipped_no_contact',v_missing);
end $$;
revoke all on function public.treasury_enqueue_weekly_invoice_notifications() from public,anon,authenticated;
grant execute on function public.treasury_enqueue_weekly_invoice_notifications() to postgres;
select cron.schedule('treasury-weekly-invoice-monday','0 17 * * 0',$$select public.treasury_enqueue_weekly_invoice_notifications();$$);
