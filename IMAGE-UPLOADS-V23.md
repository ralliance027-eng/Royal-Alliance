# Royal Alliance V23 — Image uploads and automatic storage bucket

- A shared Supabase Storage bucket named `royal-alliance-media` is created/updated by migration `20261010090000_royal_alliance_media_bucket.sql`.
- Allowed formats: PNG, JPEG, WebP. Maximum size: 5 MiB.
- Public read is enabled so saved product image URLs render in the catalog. Authenticated active staff may upload/update/delete only within their own `auth.uid()` folder.
- Draw gift/prize image upload uses `royal-alliance-media/<user-id>/prizes/...` and persists the public URL and storage path to `gifts.image_url` and `gifts.storage_path`.
- Booking product creation now accepts a file upload and persists `image_url` and `storage_path` in `booking_products`.
- Image URL entry remains available as an alternative. Draw prizes select existing gift products, so they reuse the gift image.

## Database status
The storage bucket and policies were applied to the connected Supabase project through the Supabase connection during this session. The migration file is included for reproducibility in other environments. Storage upload itself and the full browser flow still require a signed-in UI test.
