# How to set up your new databases — simple step-by-step

## What you're building

- **ONE Platform database** — just knows which companies exist and where to find them, plus Super Admin logins.
- **ONE separate database per company** — everything else for that company lives here alone: its users, use cases, dashboards, credentials, chat history, audit log. Nothing is shared with any other company, ever, because it's a genuinely different database.

## Step 1 — Do this ONCE, ever

Run `00_create_app_login_RUN_ONCE.sql` — just once, on any database. This creates the "login" your app will use to talk to Postgres from now on. **Open the file first and change the password** before running it.

## Step 2 — Create the Platform database

1. Create a new, empty database. Call it something like `ryze_platform`.
2. Run `01_platform_database.sql` against it.
3. Run `01b_grant_app_access_per_database.sql` against it too.

## Step 3 — Create a database for each real company

For **every** company (repeat this for each one):

1. Create a new, empty database, named after the company — e.g. `tenant_vantage_insurance`. Keep it lowercase, no spaces (use underscores instead).
2. Run `02_tenant_database_template.sql` against it.
3. Run `01b_grant_app_access_per_database.sql` against it too.
4. Go back to the Platform database and add one row telling it this company exists:
   ```sql
   INSERT INTO tenants (name, industry, db_name) VALUES
       ('Vantage Insurance', 'insurance', 'tenant_vantage_insurance');
   ```

## Step 4 (optional) — Add test users

If you want 2 sample logins to test with in a company's database, run `03_optional_demo_users.sql` against that company's database.

## Step 5 — Add your first Super Admin

In the Platform database:
```sql
INSERT INTO platform_admins (email, display_name) VALUES
    ('you@yourcompany.com', 'Your Name');
```

---

## ⚠️ One important thing before you can actually use any of this

These files only build the **database side**. The app's own backend code
right now only knows how to talk to **one single database at a time** — it
doesn't yet know how to figure out "which company's database do I need to
open for this particular person logging in right now?"

That's real code that needs to be written next — I have **not** built
that part yet. Once you've got your databases set up using the steps
above, tell me and I'll build that piece so the app can actually use
this new setup.
