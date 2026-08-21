# Cloud sync setup (one-time, ~5 minutes)

SAT 2048 can save your progress to a free Supabase account so the same
attempts, mistake logs, highlights, and stats show up on your laptop **and**
your phone. Here's how to turn it on.

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com), sign up (free tier is plenty),
   and click **New project**.
2. Give it any name (e.g. `sat-2048`), set a database password (you won't need
   it again for this app), and pick a region near you.

## 2. Create the tables

1. In the project dashboard, open **SQL Editor → New query**.
2. Paste the entire contents of [`supabase-setup.sql`](supabase-setup.sql) and
   click **Run**. You should see "Success. No rows returned."

> **Already set this up before?** Re-run the whole file — every statement is
> idempotent, so it only adds what's missing (the `classes` and
> `class_members` tables, the `join_class` function, and their policies).
> Existing progress, profiles, and comments are untouched. The old
> email-invite `teacher_links` table stops being used but is kept around;
> a commented-out `drop table` at the bottom removes it if you want.

## 3. Point the app at your project

1. In the dashboard, open **Project Settings → API** (or click **Connect**).
   Copy two values:
   - **Project URL** — looks like `https://abcdefgh.supabase.co`
   - **anon public** API key — a long string starting with `eyJ…` or `sb_publishable_…`
2. Open `index.html` and search for `PASTE_YOUR`. Replace the two placeholders:

   ```js
   const SUPABASE_URL = "https://abcdefgh.supabase.co";
   const SUPABASE_ANON_KEY = "eyJ...";
   ```

   The anon key is designed to be public — the row-level security rules from
   step 2 are what keep each account's data private.

## 4. Set the site URL (for confirmation / reset emails)

In **Authentication → URL Configuration**, set **Site URL** to where you play
the game, e.g. `https://rshar2027.github.io/SAT2048/`. Email confirmation and
password-reset links will send people there.

(Optional: in **Authentication → Sign In / Up → Email**, you can turn off
"Confirm email" if you'd rather skip the confirmation-email step.)

## 5. Push and play

Commit and push `index.html` so GitHub Pages serves the new version. Then, in
the game, open **Account & sync** in the sidebar:

- **Create account** with your email + a password (confirm the email if asked).
- **Sign in** on every device you use — laptop, phone, anywhere.

From then on progress saves to your account automatically a couple of seconds
after every change, and devices merge their progress instead of overwriting
each other — nothing is lost if you play offline on two devices and sync later.

The old **Save backup file / Restore** buttons still work and are a good
belt-and-suspenders copy.

## 6. Teacher accounts & classes (optional)

A teacher can watch students' progress and comment on their mistakes:

1. **Teacher:** open **Account & sync**, switch **Account type** to
   **Teacher**, and create an account. Signing in as a teacher replaces the
   game with a dashboard. Click **+ Create class**, name it (e.g. "Period 3"),
   and you get a random 6-letter join code. Copy it and give it to your
   students. Create as many classes as you like; delete one any time.
2. **Student:** sign in, open **Account & sync**, and under **Join a class**
   type the 6-letter code. Students can also set **Your name** there so the
   teacher's dashboard shows a name instead of an email. A student can join
   several classes and leave any of them later; teachers can likewise remove
   a student from a class.
3. From then on the teacher's dashboard groups students by class and shows
   each one's accuracy, per-skill breakdown, and full mistake log. Opening a
   mistake shows the exact question, the student's answers, their written
   reflection — and a comment box. Comments appear on the student's side
   wherever they review that question (question bank, statistics → recent
   attempts), marked 💬.
4. **Teacher tools**, each its own page in the dashboard sidebar:
   - **Students** — rosters per class with sort, inactivity flags, trend
     arrows, summary chips, a ⚠ *Needs your attention* strip (quiet 7+ days,
     accuracy dropping, overdue assignments), Copy code / Copy invite, and a
     one-click **.xlsx class export** (roster + every mistake + SAT scores).
   - **Assignments** — post "20 Inference questions by Friday" (skill, target,
     due date); it appears on each student's dashboard with a live progress
     bar, and the teacher sees a who's-done-it roster. Announcements post to
     the same student card.
   - **Insights** — 14-day activity chart, weakest skills, and the questions
     most students missed, openable straight into a real attempt to comment.
   - **Leaderboard** — questions this week / accuracy / streak / 2048 score.
   - **SAT Scores** — who's taken the real SAT and when, latest & best real
     scores with section breakdowns, latest practice score, each student's
     goal (hit ✓ or gap), and full test-by-test history on the student's
     profile. Students self-report under **My SAT scores** in their game
     sidebar; scores sync inside their normal progress data, so this needs
     no extra tables.

Privacy is enforced by row-level security: joining happens through a
server-side `join_class` function, students can never read the class list,
and teachers can only *read* the progress of students who joined one of
their classes — only those students see the teacher's comments.
