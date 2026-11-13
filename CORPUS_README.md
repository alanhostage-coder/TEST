# Corpus Note | HubSpot Company Record Card

Modern private app on HubSpot Projects 2026.03 for Product Updates portal **145209388**. This source is intended for an authorised HubSpot deployment and is not evidence of installation.

## What it does

- Displays an internal note entry form in a company record tab
- Persists each note to the existing Corpus Notes custom object (2-256491528)
- Creates a default association to the Company
- Displays associated note history, decisions, risks and follow-ups
- Never writes to meeting descriptions, attendees or external invitations
- Optionally stores a meeting activity ID as text, not a direct meeting association

## Deployment

Store `HUBSPOT_PERSONAL_ACCESS_KEY` as a GitHub Actions repository secret for account 145209388. Run the Upload Corpus Note workflow. Its official HubSpot Actions steps upload and deploy the project. Once built, install the private app from Development > Projects > Distribution, grant scopes, and add the card to the Company record layout via Customize > Add card > Apps. Verify with a safe test note.

Example target record:
https://app-eu1.hubspot.com/contacts/145209388/record/0-2/465468643550

## Security

The serverless function token is app-wide, not per-user. Run a record-access audit and permission review before adding real confidential notes. Do not store a secret in GitHub source. Follow least privilege. Attachment upload is intentionally deferred to the native custom object record. The list is bounded to 100 linked notes.
