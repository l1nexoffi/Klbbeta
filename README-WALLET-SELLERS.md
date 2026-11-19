# KLB STORE wallet and seller prototype

This ZIP is a **GitHub Pages demo**. Wallet balances, deposit/withdrawal requests, seller listings, and moderation are stored in browser `localStorage` so the interface can be tested. They are not shared between devices or users and are not suitable for real-money use.

## Demo flow
- The catalog is emptied on first load (one-time `klb_products_cleared_v1` marker).
- Users can create a deposit request; a five-digit comment code is generated.
- Admin can set demo deposit bank/card details in Admin → Settings.
- Admin → Пополнения can confirm/reject requests. Confirming adds demo balance.
- Withdrawal requests support bank+phone or USDT TRC20; balance is reserved in the demo. Rejection refunds it.
- Seller requests are handled in Admin → Продавцы. Approved demo users need to sign out and back in to see the seller panel.
- Sellers create listings with image, description, category, price, quantity; listings are submitted for moderation.
- Admin → Модерация can publish or reject listings.

## Before real money / hosting
1. Configure Supabase Auth and remove the local demo authentication.
2. Run `wallet-marketplace-migration.sql` only after the existing `profiles` table and `public.is_admin()` function are confirmed. The project currently has schema differences from the SQL previously run in the Supabase project; review those differences before applying.
3. Connect the UI to the RPCs in the migration. Never update wallet balances directly from client JavaScript.
4. Store card/recipient instructions in a protected database setting and expose them through the authenticated RPC.
5. Use Supabase Storage for listing images (not localStorage/base64).
6. Verify seller approval, admin authorization, wallet ledger and all RPCs with two test accounts before production.
7. Do not commit service-role keys, passwords, card details, or private wallet keys.

The current client prototype intentionally does not claim to be a production payment system.
