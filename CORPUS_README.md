# Corpus Notes by Siloy UKI | HubSpot Company Record App

Private app on HubSpot Projects 2026.03 for Product Updates portal **145209388**. This source is intended for an authorised HubSpot deployment and is not evidence of installation.

## What it does

- Displays an internal note entry form in a company record tab
- Persists each note to the existing Corpus Notes custom object (2-256491528)
- Creates a default association to the Company
- Displays associated note history, decisions, risks and follow-ups
- Never writes to meeting descriptions, attendees or external invitations
- Optionally stores a meeting activity ID as text, not a direct meeting association

## Corpus Notes by Siloy UKI

**Default product branding:** Siloy UKI, sourced from [Siloy brand](https://siloy.com/brand).
Default palette: near-black `#010103`, powder blue `#DAEAFF`, warm yellow `#FEF5AC`,
mint `#EAFDD6`. Native CRM form controls retain HubSpot's own typography and interaction patterns.

The Company's card is intentionally a **quiet internal workspace**, not a long CRM form:
- A distinct INTERNAL ONLY header, Siloy logo/monogram, and explicit explanation that notes are not sent to calendar attendees
- A quick note flow with title, note type and body only; today's date is prefilled
- Optional details on demand for note date, decisions, risks, next actions, follow-up date, and meeting activity reference
- A two-step discard action; unsuccessful saves leave the draft intact
- A successful save receipt with a link to the stored Corpus Note
- Recent associated notes shown first, with expandable history and links to each native record
- A visible caveat that INTERNAL ONLY is an interface convention, **not** a security guarantee

### White-label configuration for customers

The app defaults to **Siloy UKI** with no configuration. To provide another company's identity:

1. Go to GitHub Actions > **Upload and deploy Corpus Note to HubSpot** > **Run workflow**, branch `codex/corpus-note-hubspot-card`.
2. Enter the **brand_website** as a public HTTPS URL, for example `https://customer.example.org`.
3. Enter **brand_name** if you want to override the detected website identity.
4. Optionally supply:
   - **brand_accent**: main accent, e.g. `#DAEAFF`
   - **brand_background**: banner background, e.g. `#010103`
   - **brand_highlight**: internal-only pill colour, e.g. `#FEF5AC`
   - **brand_logo_url**: public PNG, JPEG, or WebP image hosted on the **same domain** as `brand_website`
5. Run the deployment. The static generator embeds any supplied logo safely into the bundled header and saves a non-sensitive `brand-config.js`.
6. To retain the chosen identity on subsequent automatic push builds, save corresponding GitHub Actions repository variables `CORPUS_BRAND_URL`, `CORPUS_BRAND_NAME`, `CORPUS_BRAND_ACCENT`, `CORPUS_BRAND_BACKGROUND`, `CORPUS_BRAND_HIGHLIGHT`, `CORPUS_BRAND_LOGO_URL`.

The URL-to-logo/colour scan runs **once during deployment**. No external brand website calls occur when an internal note is being written.

These options are **developer/deployment settings**, not yet an in-app admin settings page. For a reusable commercial app, a per-account settings page, configuration storage, permissions policy and rollout process should be delivered next.

HubSpot UI extensions do not permit arbitrary CSS or webfont injection into the native CRM card. Native controls remain accessible and consistent with the CRM. The branded banner uses a bundled SVG asset and safe fallbacks.

## Deployment

Store `HUBSPOT_PERSONAL_ACCESS_KEY` as a GitHub Actions repository secret for account 145209388. Run the Upload Corpus Note workflow. Its official HubSpot Actions steps upload and deploy the project. Once built, install the private app from Development > Projects > Distribution, grant scopes, and add the card to the Company record layout via Customize > Add card > Apps. Verify with a safe test note.

Example target record:
https://app-eu1.hubspot.com/contacts/145209388/record/0-2/465468643550

## Security

The serverless function token is app-wide, not per-user. Run a record-access audit and permission review before adding real confidential notes. Do not store a secret in GitHub source. Follow least privilege. Attachment upload is intentionally deferred to the native custom object record. The list is bounded to 100 linked notes.
