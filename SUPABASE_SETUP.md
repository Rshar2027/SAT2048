# Cloud sync setup (one-time, ~5 minutes)

SAT 2048 can save your progress to a free Supabase account so the same
attempts, mistake logs, highlights, and stats show up on your laptop **and**
your phone. Here's how to turn it on.

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com), sign up (free tier is plenty),
   and click **New project**.
2. Give it any name (e.g. `sat-2048`), set a database password (you won't need
   it again for this app), and pick a region near you.

## 2. Create the progress table

1. In the project dashboard, open **SQL Editor → New query**.
2. Paste the entire contents of [`supabase-setup.sql`](supabase-setup.sql) and
   click **Run**. You should see "Success. No rows returned."

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
