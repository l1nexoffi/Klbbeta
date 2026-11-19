# KLB STORE — real backend setup (Supabase)

This package contains the first production-backend layer for KLB STORE. The existing HTML demo is still static/local-storage and **is not yet switched to this backend**. Do not present the demo as a live marketplace until the frontend integration is completed and tested.

## Why this is required
GitHub Pages cannot host a database or secure server-side authentication. Supabase supplies PostgreSQL + Auth. The frontend may remain on GitHub Pages or your hosting provider, but the data/auth services are shared.

## Setup
1. Create a Supabase project at https://supabase.com.
2. Open SQL Editor and run `supabase-schema.sql`.
3. In Authentication settings, disable email confirmation for the username-only account flow (synthetic email addresses are used). This is a trade-off; use email/OTP instead if you need verified identities.
4. Copy `supabase-config.example.js` to `supabase-config.js`; fill the project URL and the public anon/publishable key from Project Settings → API. Never put a `service_role` key in frontend files.
5. Add scripts to the frontend pages in this order:
   `<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>`
   `<script src="supabase-config.js"></script>`
   `<script src="backend.js"></script>`
6. Register the administrator through the registration UI once the UI is wired to `KLBBackend.register()`.
7. In Supabase SQL Editor, promote the account:
   `UPDATE public.profiles SET role='admin' WHERE username='Kolobok';`
8. Set a strong unique password in the account. The requested demo password `kolobokad` is weak and should not be used for a live admin account.

## Database tables
- `profiles`: account username, role and status
- `seller_applications`: seller applications and review status
- `products`: seller listings and moderation
- `orders`: purchase/order records
- `favorites`: user favorites
- `reviews`: completed-order reviews

## Current limitation
`backend.js` exposes basic Supabase operations, but the existing storefront/admin UI still uses local demo storage. The next engineering step is to replace its localStorage data paths with calls to this API and add the server-side admin CRUD screens. Payment integration is not included; orders currently represent unpaid order requests only.
