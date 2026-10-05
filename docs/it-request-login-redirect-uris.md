# IT request — add localhost redirect URIs to the SCoR Dashboard LOGIN app

## Summary
Local/dev sign-in to the SCoR Dashboard is failing because the **login Entra app** no longer has the
`localhost` **redirect URIs** registered. Signing in from a local dev container returns **AADSTS50011**
("the redirect URI specified in the request does not match the redirect URIs configured for the
application"). We need **both** of the following added back to this app's redirect URIs, so dev testing
works whether the container is on port 3000 or 3001:

- `http://localhost:3000/api/auth/callback/microsoft-entra-id`
- `http://localhost:3001/api/auth/callback/microsoft-entra-id`

**Do not remove the production redirect URI** `https://data.tcrce.ca/api/auth/callback/microsoft-entra-id`
— it must stay.

## The application (the LOGIN app — user sign-in; NOT the data SP)
- **Name:** `TCRCE Data Web App`
- **Role:** the Entra app the SCoR Dashboard uses for **user sign-in** (the "login" app in our login/data split).
- **App (client) ID:** `819f9480-5e65-469e-be27-89ac30381f1f`
- **Tenant ID:** `0320ef6f-7349-4acf-b62a-e780da155b7e`
- **Confirmed 2026-10-05:** the `localhost` redirect URIs are **not currently present** on this app's
  Authentication → Web → Redirect URIs (only the production URI remains), which is what breaks local sign-in.
- This is a **different** app from the data service principal in the OneLake request
  (`StudentDataAssessment`, `c33fb2d3-…`). That one is about `COPY INTO`; this one is about sign-in.

## Exact symptom
Opening the app locally and clicking sign-in redirects to Microsoft, then errors:

> **AADSTS50011**: The redirect URI `http://localhost:3000/api/auth/callback/microsoft-entra-id`
> specified in the request does not match the redirect URIs configured for the application `819f9480-…`.

Production sign-in at `https://data.tcrce.ca` is unaffected — only the `localhost` URIs are missing.

## What we need
1. In the login app's **Authentication** blade → **Web** platform → **Redirect URIs**, add the two
   `localhost` URIs listed above (3000 and 3001), keeping the existing `https://data.tcrce.ca` URI.
2. **Going forward:** please notify the project lead before modifying these app registrations / their
   redirect URIs — local sign-in breaks silently otherwise. This `localhost:3000` redirect URI was
   removed once before (same incident class as the data SP's OneLake access change); re-adding both
   ports now avoids repeat breakage.

## How to confirm it's fixed
Run the dev container on `localhost:3000` (and/or `:3001`) and sign in with Microsoft Entra — the OAuth
flow completes and lands back in the app instead of showing AADSTS50011.
