# KLB STORE — marketplace demo

Static GitHub Pages demo with local browser storage. Upload all files in this folder to the repository root.

## Pages
- `index.html` — marketplace catalog, account/profile, favorites, test orders, seller application
- `admin-login.html` — admin password confirmation (requires logged-in Kolobok admin account)
- `admin.html` — demo admin dashboard

## Demo admin account
- Site login: `Kolobok`
- Site password: `kolobok`
- Admin-panel confirmation password: `kolobokad`

Change these demo credentials in `script.js` and `auth.js` before sharing the demo. Credentials and account data are client-side and are **not secure**. GitHub Pages cannot provide server-side authentication, private data, or cross-device persistence.

## Features
- Local registration/login and profile
- Profile statistics and test order history
- Favorites per browser account
- Test order creation from catalog
- Seller application form with username, description, benefit, age and Telegram
- Seller applications displayed in admin dashboard; approve/decline
- Admin demo management of listings, orders, users, seller applications, settings

## Production deployment
A backend and database are required for secure authentication, real orders/payments, shared user data, seller inventory, and admin permissions. Static frontend is intentionally structured as a prototype only.
