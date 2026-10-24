# V70 — Member Edit & Assign visibility fix

The V69 `OperationalSections.jsx` already includes Edit, Assign, and WhatsApp in the members table `renderActions`.
If the running browser shows only WhatsApp, it is almost certainly running a different/older project folder or old Next.js process; the CSS change here also prevents action buttons from shrinking/wrapping out of view.

## Apply to the correct running project
1. Stop the currently running dev server with Ctrl+C.
2. Extract this ZIP into the project folder you actually run from VS Code (the folder containing package.json).
3. Confirm `app/dashboard/OperationalSections.jsx` includes `Pencil` + `Users` and the Members `renderActions` with Edit and Assign.
4. Restart with `npm run dev` and hard-refresh the browser with Ctrl+Shift+R.
5. Confirm the Action column shows Edit, Assign, WhatsApp.

Note: this is a frontend visibility/layout patch. Database RPC/migration deployment and live role-based assignment E2E must still be verified separately.
