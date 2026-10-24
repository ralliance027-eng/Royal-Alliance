# Royal Alliance V35 — Send from the logged-in operator's WhatsApp

- Added `Open My WhatsApp + Copy Message` to the manual WhatsApp popup.
- Opens `wa.me/<saved-recipient-number>?text=<encoded-message>` so the current operator's default WhatsApp Web/app session is used, not the Meta Cloud API sender.
- Copies the editable message to the clipboard when browser permission is available.
- Records a `notification_logs` row with `status='manual_opened'`, recipient, message body and consent flag. This means chat opened/prepared only; it does not claim the operator pressed Send or that the message was delivered.
- Preserved the separate `Send via Business API` path for Meta API delivery.
- Validation: `npm run check:release` passed. `npm run build` could not run because `next` is not installed in the working environment; production build remains uncertified.
