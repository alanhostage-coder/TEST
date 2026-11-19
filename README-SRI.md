# Siloy Revenue Intelligence | Action v0.4

**Target:** Siloy UKI Apps, HubSpot developer test portal **149783010**. Isolated release from Notes and Time.

## Real capabilities
- **Live Triage:** On-demand ranked queue from the 100 most recently modified open Deals. Includes rule reasons, proposed next steps and total value of high-attention Deals (not a revenue-loss forecast). If the portal has more than 100 open Deals, ranking is explicitly labelled a partial scan.
- **Bulk safety:** Search does not provide trustworthy contact association counts. The queue skips the 15-point missing-contact penalty and communicates that difference. Individual Deal cards can assess associations.
- **Human review:** In-record Deal card calculates and previews the assessment; saving updates only the existing six SRI Deal properties. Once saved, a reviewer can explicitly mark it Reviewed, protected by last-assessed timestamp matching. No tasks or emails are sent.
- **Scenario preview:** When the portal has no open Deals, an opt-in example queue is clearly labelled as not real CRM data, and cannot be saved.
- **Credits:** Routine triage and assessment use zero AI credits.

## Build & release
Pushing `codex/sri-action-hubspot` runs `.github/workflows/sri-action-ship.yml` with the existing portal 149783010-bound HubSpot developer credential secret. It tests, validates, uploads, deploys and verifies app installation. Source-only UAT is not equivalent to record-layout UAT. Tests: `node --test tests/*.test.cjs`.

## Remaining UAT gates
1. Verify live App Page appears and its explicit scenario preview works in an empty portal.
2. Verify card placement in the Deal right sidebar (installation does not prove layout activation).
3. On an authorised Deal, verify the full score, manual Save, Mark Reviewed, stale assessment behaviour and absence of other CRM writes.
4. Reconfirm no change to Siloy Notes or Siloy Time. No Deals are auto-created.
5. Find and Insight remain roadmap modules. Client / production distribution remains disabled.
