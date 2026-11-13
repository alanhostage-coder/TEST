# Corpus Note | HubSpot Company Record Card

Modern private app on HubSpot Projects 2026.03 for Product Updates portal **145209388**. This source is intended for an authorised HubSpot deployment and is not evidence of installation.

## What it does

- Displays an internal note entry form in a company record tab
- Persists each note to the existing Corpus Notes custom object (2-256491528)
- Creates a default association to the Company
- Displays associated note history, decisions, risks and follow-ups
- Never writes to meeting descriptions, attendees or external invitations
- Optionally stores a meeting activity ID as text, not a direct meeting association

## Organisation branding

Corpus Note has a **native-card safe** brand treatment: a logo/monogram banner,
the organisation display name, a contrasting accent and an explicit INTERNAL ONLY
marker. The marker describes the *workflow*; it is not an access-control guarantee.

To configure a client installation:

1. Open GitHub Actions > **Upload and deploy Corpus Note to HubSpot** > **Run workflow** on `codex/corpus-note-hubspot-card`.
2. Provide **brand_website** (the public HTTPS URL, e.g. `https://www.prosperohub.com`).
3. Optionally provide **brand_name** and **brand_accent** (`#RRGGBB` or `#RGB`).
4. Run the workflow. The deployment-time script `scripts/configure-corpus-brand.mjs` attempts to read the public site's `theme-color`, page name and favicon. If these are unavailable, it uses a colour fallback and a monogram. The built card contains an SVG brand banner, not a runtime request to the site.
5. For settings to **survive subsequent push deployments**, also set the GitHub Actions repository variables `CORPUS_BRAND_URL`, `CORPUS_BRAND_NAME`, and optionally `CORPUS_BRAND_ACCENT`; manual workflow inputs only apply to the run in which they are entered.

HubSpot UI extensions do **not** support arbitrary CSS or webfonts in native CRM app cards. Logo, text, layout and status styling use supported native UI components; palette and lettering are applied inside the static SVG banner only. Full bespoke colour and font skins would require a separate custom-hosted experience. This is an install-time brand configuration, not an in-card settings editor.

## Deployment

Store `HUBSPOT_PERSONAL_ACCESS_KEY` as a GitHub Actions repository secret for account 145209388. Run the Upload Corpus Note workflow. Its official HubSpot Actions steps upload and deploy the project. Once built, install the private app from Development > Projects > Distribution, grant scopes, and add the card to the Company record layout via Customize > Add card > Apps. Verify with a safe test note.

Example target record:
https://app-eu1.hubspot.com/contacts/145209388/record/0-2/465468643550

## Security

The serverless function token is app-wide, not per-user. Run a record-access audit and permission review before adding real confidential notes. Do not store a secret in GitHub source. Follow least privilege. Attachment upload is intentionally deferred to the native custom object record. The list is bounded to 100 linked notes.
