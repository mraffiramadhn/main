# RamaSpace Trax
POS prototype for product catalog, inventory, checkout and sales history.

## Deployment
- This app is published under `/trax/` on the existing GitHub Pages site for `ramaspace.my.id`.
- The existing Pages workflow deploys the repository root on pushes to `main`.
- Supabase project: `ramaspace-trax` (Asia Pacific Southeast 1).
- Browser uses the Supabase publishable key only; never place a service-role/secret key in frontend code.

## Database
The schema migration is applied in the connected Supabase project and mirrored in `supabase/migrations/20261027000000_create_trax_pos_tables.sql`.
RLS policies scope products, payment methods, and sales to the authenticated owner.

## Important limitations
This is an early beta, not a payment processor. QRIS and bank-transfer payments require manual verification. Stock updates and sale creation are separate browser requests and are not yet an atomic database transaction; do not rely on it as the sole inventory/accounting system until a transactional RPC and end-to-end testing are added.
