# Goodminton

Badminton club tracker (PB Anomaly). Single page `index.html`, data in Supabase.

- Everyone can view. Only admins (listed in the `admins` table) can edit.
- The anon key in `index.html` is a public key and is safe to publish; row-level security protects the data.
- `setup.sql` and `seed.sql` are the database setup and the Jul to Nov 2026 data (already applied).
