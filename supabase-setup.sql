-- SAT 2048 cloud sync — run this ONCE in your Supabase project.
-- Dashboard → SQL Editor → New query → paste everything → Run.

-- One row per account holding the entire app state as JSON.
create table if not exists public.progress (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  state      jsonb not null,
  updated_at timestamptz not null default now()
);

-- Row-level security: each signed-in user can only touch their own row.
alter table public.progress enable row level security;

create policy "Users can read own progress"
  on public.progress for select
  using (auth.uid() = user_id);

create policy "Users can insert own progress"
  on public.progress for insert
  with check (auth.uid() = user_id);

create policy "Users can update own progress"
  on public.progress for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own progress"
  on public.progress for delete
  using (auth.uid() = user_id);

-- ============ Teacher accounts ============
-- Run everything below even if you set up the progress table earlier —
-- it only ADDS tables and policies, nothing existing is touched.

-- Who is who: one row per account, role picked at signup.
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  email      text not null,
  role       text not null default 'student' check (role in ('student', 'teacher')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Everyone signed in can see teacher profiles (so students can add a teacher
-- by email); beyond that you can only see your own row.
create policy "Read own profile or any teacher"
  on public.profiles for select
  using (auth.uid() = user_id or role = 'teacher');

create policy "Insert own profile"
  on public.profiles for insert
  with check (auth.uid() = user_id);

create policy "Update own profile"
  on public.profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Student ↔ teacher links. Created by the student ("add a teacher"),
-- removable by either side. Emails are stored so each side can display the
-- other without extra read permissions.
create table if not exists public.teacher_links (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references auth.users (id) on delete cascade,
  teacher_id    uuid not null references auth.users (id) on delete cascade,
  student_email text not null,
  teacher_email text not null,
  created_at    timestamptz not null default now(),
  unique (student_id, teacher_id)
);

alter table public.teacher_links enable row level security;

create policy "Link parties can read"
  on public.teacher_links for select
  using (auth.uid() = student_id or auth.uid() = teacher_id);

-- Only the student can create the link, and only to a real teacher account.
create policy "Students link themselves to a teacher"
  on public.teacher_links for insert
  with check (
    auth.uid() = student_id
    and exists (
      select 1 from public.profiles p
      where p.user_id = teacher_id and p.role = 'teacher'
    )
  );

create policy "Either side can remove the link"
  on public.teacher_links for delete
  using (auth.uid() = student_id or auth.uid() = teacher_id);

-- Linked teachers may READ (never write) their students' progress.
create policy "Teachers can read linked students' progress"
  on public.progress for select
  using (
    exists (
      select 1 from public.teacher_links tl
      where tl.student_id = progress.user_id
        and tl.teacher_id = auth.uid()
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

create policy "Comment parties can read"
  on public.comments for select
  using (auth.uid() = student_id or auth.uid() = teacher_id);

-- Teachers comment only on students who shared with them.
create policy "Linked teachers can comment"
  on public.comments for insert
  with check (
    auth.uid() = teacher_id
    and exists (
      select 1 from public.teacher_links tl
      where tl.student_id = comments.student_id
        and tl.teacher_id = auth.uid()
    )
  );

create policy "Teachers can edit own comments"
  on public.comments for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

create policy "Teachers can delete own comments"
  on public.comments for delete
  using (auth.uid() = teacher_id);
