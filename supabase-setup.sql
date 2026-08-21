-- SAT 2048 cloud sync — run this in your Supabase project.
-- Dashboard → SQL Editor → New query → paste everything → Run.
-- Safe to re-run: every statement is idempotent (drop-if-exists + create).

-- One row per account holding the entire app state as JSON.
create table if not exists public.progress (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  state      jsonb not null,
  updated_at timestamptz not null default now()
);

-- Row-level security: each signed-in user can only touch their own row.
alter table public.progress enable row level security;

drop policy if exists "Users can read own progress" on public.progress;
create policy "Users can read own progress"
  on public.progress for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own progress" on public.progress;
create policy "Users can insert own progress"
  on public.progress for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own progress" on public.progress;
create policy "Users can update own progress"
  on public.progress for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own progress" on public.progress;
create policy "Users can delete own progress"
  on public.progress for delete
  using (auth.uid() = user_id);

-- ============ Teacher accounts ============

-- Who is who: one row per account, role picked at signup.
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  email      text not null,
  role       text not null default 'student' check (role in ('student', 'teacher')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "Read own profile or any teacher" on public.profiles;
create policy "Read own profile or any teacher"
  on public.profiles for select
  using (auth.uid() = user_id or role = 'teacher');

drop policy if exists "Insert own profile" on public.profiles;
create policy "Insert own profile"
  on public.profiles for insert
  with check (auth.uid() = user_id);

drop policy if exists "Update own profile" on public.profiles;
create policy "Update own profile"
  on public.profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============ Classes (join by 6-letter code) ============
-- A teacher creates a class and gets a random 6-letter code. Students type
-- that code into "Join a class" — no email invites in either direction.

create table if not exists public.classes (
  id            uuid primary key default gen_random_uuid(),
  teacher_id    uuid not null references auth.users (id) on delete cascade,
  teacher_email text not null,
  name          text not null check (char_length(name) between 1 and 60),
  code          text not null unique check (code ~ '^[A-Z]{6}$'),
  created_at    timestamptz not null default now()
);

alter table public.classes enable row level security;

drop policy if exists "Teachers read own classes" on public.classes;
create policy "Teachers read own classes"
  on public.classes for select
  using (auth.uid() = teacher_id);

-- Only real teacher accounts can create classes, and only as themselves.
drop policy if exists "Teachers create own classes" on public.classes;
create policy "Teachers create own classes"
  on public.classes for insert
  with check (
    auth.uid() = teacher_id
    and exists (
      select 1 from public.profiles p
      where p.user_id = auth.uid() and p.role = 'teacher'
    )
  );

drop policy if exists "Teachers delete own classes" on public.classes;
create policy "Teachers delete own classes"
  on public.classes for delete
  using (auth.uid() = teacher_id);

-- One row per student per class. Class/teacher fields are denormalized so
-- each side can render the other without extra read permissions, and so no
-- policy here has to reference `classes` (which would recurse).
create table if not exists public.class_members (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references public.classes (id) on delete cascade,
  class_name    text not null,
  class_code    text not null,
  teacher_id    uuid not null references auth.users (id) on delete cascade,
  teacher_email text not null,
  student_id    uuid not null references auth.users (id) on delete cascade,
  student_email text not null,
  student_name  text,
  created_at    timestamptz not null default now(),
  unique (class_id, student_id)
);

create index if not exists class_members_student_idx on public.class_members (student_id);
create index if not exists class_members_teacher_idx on public.class_members (teacher_id);

alter table public.class_members enable row level security;

drop policy if exists "Members and their teacher can read" on public.class_members;
create policy "Members and their teacher can read"
  on public.class_members for select
  using (auth.uid() = student_id or auth.uid() = teacher_id);

-- Rows are created only by the join_class() function below (security definer),
-- so there is deliberately NO insert policy — nobody can insert directly.

-- A student can leave; a teacher can remove a student from their class.
drop policy if exists "Student leaves or teacher removes" on public.class_members;
create policy "Student leaves or teacher removes"
  on public.class_members for delete
  using (auth.uid() = student_id or auth.uid() = teacher_id);

-- Students may refresh the display name on their own membership rows.
drop policy if exists "Students update own member name" on public.class_members;
create policy "Students update own member name"
  on public.class_members for update
  using (auth.uid() = student_id)
  with check (auth.uid() = student_id);

-- Joining happens through this function so students never need read access
-- to the classes table (the code alone is the credential).
create or replace function public.join_class(p_code text, p_name text default '')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c        public.classes%rowtype;
  my_email text;
  my_role  text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'You must be signed in to join a class.');
  end if;
  select email, role into my_email, my_role from public.profiles where user_id = auth.uid();
  if my_role = 'teacher' then
    return jsonb_build_object('ok', false, 'error', 'Teacher accounts can''t join a class — create your own from the dashboard.');
  end if;
  select * into c from public.classes where code = upper(trim(p_code));
  if not found then
    return jsonb_build_object('ok', false, 'error', 'No class found with that code — double-check it with your teacher.');
  end if;
  insert into public.class_members
    (class_id, class_name, class_code, teacher_id, teacher_email, student_id, student_email, student_name)
  values
    (c.id, c.name, c.code, c.teacher_id, c.teacher_email, auth.uid(),
     coalesce(my_email, auth.jwt() ->> 'email', ''), nullif(trim(coalesce(p_name, '')), ''))
  on conflict (class_id, student_id) do nothing;
  return jsonb_build_object('ok', true, 'class_name', c.name, 'class_code', c.code, 'teacher_email', c.teacher_email);
end;
$$;

revoke all on function public.join_class(text, text) from public;
grant execute on function public.join_class(text, text) to authenticated;

-- Assignments & announcements a teacher posts to a class. Students read the
-- posts for classes they're members of; assignment completion is computed
-- client-side from each student's synced attempts (no write-back needed).
create table if not exists public.class_posts (
  id         uuid primary key default gen_random_uuid(),
  class_id   uuid not null references public.classes (id) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  kind       text not null check (kind in ('assignment', 'announcement')),
  title      text not null check (char_length(title) between 1 and 200),
  body       text check (char_length(body) <= 2000),
  skills     jsonb,        -- assignment: array of skill names; null/[] = any skill
  target     int check (target is null or target between 1 and 500),
  due_at     timestamptz,  -- assignment: optional due date
  created_at timestamptz not null default now()
);

create index if not exists class_posts_class_idx on public.class_posts (class_id);

alter table public.class_posts enable row level security;

drop policy if exists "Teacher or class members can read posts" on public.class_posts;
create policy "Teacher or class members can read posts"
  on public.class_posts for select
  using (
    auth.uid() = teacher_id
    or exists (
      select 1 from public.class_members m
      where m.class_id = class_posts.class_id
        and m.student_id = auth.uid()
    )
  );

drop policy if exists "Teachers post to own classes" on public.class_posts;
create policy "Teachers post to own classes"
  on public.class_posts for insert
  with check (
    auth.uid() = teacher_id
    and exists (
      select 1 from public.classes c
      where c.id = class_posts.class_id and c.teacher_id = auth.uid()
    )
  );

drop policy if exists "Teachers edit own posts" on public.class_posts;
create policy "Teachers edit own posts"
  on public.class_posts for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

drop policy if exists "Teachers delete own posts" on public.class_posts;
create policy "Teachers delete own posts"
  on public.class_posts for delete
  using (auth.uid() = teacher_id);

-- Teachers may READ (never write) the progress of students in their classes.
drop policy if exists "Teachers can read linked students' progress" on public.progress;
drop policy if exists "Teachers can read class students' progress" on public.progress;
create policy "Teachers can read class students' progress"
  on public.progress for select
  using (
    exists (
      select 1 from public.class_members m
      where m.student_id = progress.user_id
        and m.teacher_id = auth.uid()
    )
  );

-- Teacher comments on a student's questions.
create table if not exists public.comments (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references auth.users (id) on delete cascade,
  teacher_id    uuid not null references auth.users (id) on delete cascade,
  teacher_email text not null,
  question_id   text not null,
  attempt_at    text,
  body          text not null check (char_length(body) between 1 and 4000),
  created_at    timestamptz not null default now()
);

alter table public.comments enable row level security;

drop policy if exists "Comment parties can read" on public.comments;
create policy "Comment parties can read"
  on public.comments for select
  using (auth.uid() = student_id or auth.uid() = teacher_id);

-- Teachers comment only on students who are in one of their classes.
drop policy if exists "Linked teachers can comment" on public.comments;
drop policy if exists "Class teachers can comment" on public.comments;
create policy "Class teachers can comment"
  on public.comments for insert
  with check (
    auth.uid() = teacher_id
    and exists (
      select 1 from public.class_members m
      where m.student_id = comments.student_id
        and m.teacher_id = auth.uid()
    )
  );

drop policy if exists "Teachers can edit own comments" on public.comments;
create policy "Teachers can edit own comments"
  on public.comments for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

drop policy if exists "Teachers can delete own comments" on public.comments;
create policy "Teachers can delete own comments"
  on public.comments for delete
  using (auth.uid() = teacher_id);

-- ============ Migration from the old email-invite system ============
-- The teacher_links table powered the old "student adds a teacher by email"
-- flow. Its access policies are gone (dropped above); the table itself is
-- kept so no data is destroyed. Uncomment to remove it entirely:
-- drop table if exists public.teacher_links;
