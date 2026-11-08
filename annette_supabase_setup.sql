-- ANNETTE CAMPUZANO ONLINE FITNESS
-- Esquema inicial seguro para Supabase.
-- Ejecutar en Supabase > SQL Editor > New query.
-- Este script NO crea cuentas ni asigna administradoras todavía.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'client' check (role in ('admin', 'client')),
  access_started_at timestamptz,
  access_expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.exercise_library (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  video_url text,
  thumbnail_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.client_routines (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(user_id) on delete cascade,
  title text not null,
  week_number integer not null default 1 check (week_number between 1 and 5),
  day_label text,
  instructions text,
  starts_on date,
  ends_on date,
  created_at timestamptz not null default now()
);

create table if not exists public.routine_exercises (
  id uuid primary key default gen_random_uuid(),
  routine_id uuid not null references public.client_routines(id) on delete cascade,
  exercise_id uuid references public.exercise_library(id) on delete set null,
  exercise_name text not null,
  sets integer,
  reps text,
  rest_seconds integer,
  video_url text,
  sort_order integer not null default 0
);

create table if not exists public.meal_plans (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(user_id) on delete cascade,
  title text not null default 'Plan de alimentación',
  plan_content jsonb not null default '{}'::jsonb,
  starts_on date,
  ends_on date,
  created_at timestamptz not null default now()
);

create table if not exists public.progress_entries (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(user_id) on delete cascade,
  recorded_on date not null default current_date,
  weight_kg numeric(6,2),
  waist_cm numeric(6,2),
  hips_cm numeric(6,2),
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists client_routines_client_id_idx on public.client_routines(client_id);
create index if not exists meal_plans_client_id_idx on public.meal_plans(client_id);
create index if not exists progress_entries_client_date_idx on public.progress_entries(client_id, recorded_on desc);
create index if not exists routine_exercises_routine_id_idx on public.routine_exercises(routine_id);

-- Crear automáticamente el perfil básico cuando una persona se registra.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'client'
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Función auxiliar para reconocer administradoras sin permitir que una clienta
-- cambie su propio rol desde la aplicación.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.user_id = (select auth.uid())
      and p.role = 'admin'
  );
$$;

-- Activa o renueva 30 días. Si aún tiene días vigentes, suma 30 a la fecha
-- de vencimiento actual; si ya venció, empieza desde el momento de renovación.
create or replace function public.activate_client_30_days(target_user_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_expiry timestamptz;
begin
  if not public.is_admin() then
    raise exception 'Solo administración puede activar accesos';
  end if;

  update public.profiles
  set
    access_started_at = case
      when access_expires_at is not null and access_expires_at > now()
        then coalesce(access_started_at, now())
      else now()
    end,
    access_expires_at = case
      when access_expires_at is not null and access_expires_at > now()
        then access_expires_at + interval '30 days'
      else now() + interval '30 days'
    end
  where user_id = target_user_id
  returning access_expires_at into new_expiry;

  if new_expiry is null then
    raise exception 'No existe ese perfil de clienta';
  end if;

  return new_expiry;
end;
$$;

alter table public.profiles enable row level security;
alter table public.exercise_library enable row level security;
alter table public.client_routines enable row level security;
alter table public.routine_exercises enable row level security;
alter table public.meal_plans enable row level security;
alter table public.progress_entries enable row level security;

-- Perfiles: cada usuaria ve el suyo; administración ve todos.
drop policy if exists "profile_select_own_or_admin" on public.profiles;
create policy "profile_select_own_or_admin"
on public.profiles for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());

-- Solo administración puede modificar perfiles, roles y fechas de acceso.
-- Las clientas no reciben permiso de UPDATE sobre su perfil.
drop policy if exists "profile_update_own_name" on public.profiles;
drop policy if exists "profile_admin_manage" on public.profiles;
create policy "profile_admin_manage"
on public.profiles for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- La biblioteca de ejercicios se muestra solo a clientas con acceso vigente o admin.
drop policy if exists "exercise_read_active_or_admin" on public.exercise_library;
create policy "exercise_read_active_or_admin"
on public.exercise_library for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid())
      and p.role = 'client'
      and p.access_expires_at > now()
  )
);
drop policy if exists "exercise_admin_manage" on public.exercise_library;
create policy "exercise_admin_manage"
on public.exercise_library for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Rutinas: solo la clienta asignada con acceso vigente, o administración.
drop policy if exists "routines_read_owner_active_or_admin" on public.client_routines;
create policy "routines_read_owner_active_or_admin"
on public.client_routines for select to authenticated
using (
  public.is_admin()
  or (
    client_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.user_id = (select auth.uid())
        and p.access_expires_at > now()
    )
  )
);
drop policy if exists "routines_admin_manage" on public.client_routines;
create policy "routines_admin_manage"
on public.client_routines for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Ejercicios dentro de rutinas: se hereda el acceso de la rutina.
drop policy if exists "routine_exercises_read_owner_active_or_admin" on public.routine_exercises;
create policy "routine_exercises_read_owner_active_or_admin"
on public.routine_exercises for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.client_routines r
    join public.profiles p on p.user_id = r.client_id
    where r.id = routine_exercises.routine_id
      and r.client_id = (select auth.uid())
      and p.access_expires_at > now()
  )
);
drop policy if exists "routine_exercises_admin_manage" on public.routine_exercises;
create policy "routine_exercises_admin_manage"
on public.routine_exercises for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Alimentación: solo la clienta asignada con acceso vigente, o administración.
drop policy if exists "meal_plans_read_owner_active_or_admin" on public.meal_plans;
create policy "meal_plans_read_owner_active_or_admin"
on public.meal_plans for select to authenticated
using (
  public.is_admin()
  or (
    client_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.user_id = (select auth.uid())
        and p.access_expires_at > now()
    )
  )
);
drop policy if exists "meal_plans_admin_manage" on public.meal_plans;
create policy "meal_plans_admin_manage"
on public.meal_plans for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Progreso: clienta con acceso vigente registra y consulta solo sus datos.
drop policy if exists "progress_read_owner_active_or_admin" on public.progress_entries;
create policy "progress_read_owner_active_or_admin"
on public.progress_entries for select to authenticated
using (
  public.is_admin()
  or (
    client_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.user_id = (select auth.uid())
        and p.access_expires_at > now()
    )
  )
);
drop policy if exists "progress_insert_owner_active" on public.progress_entries;
create policy "progress_insert_owner_active"
on public.progress_entries for insert to authenticated
with check (
  client_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid())
      and p.access_expires_at > now()
  )
);
drop policy if exists "progress_admin_manage" on public.progress_entries;
create policy "progress_admin_manage"
on public.progress_entries for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Importante: no se concede acceso público/anónimo a estas tablas.
