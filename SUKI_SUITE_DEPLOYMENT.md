# Siloy UKI Apps | Repeatable HubSpot deployment

**Reference portal:** Siloy UKI Apps (`149783010`), HubSpot developer test account, EU1. Never deploy this reference installer to another portal by changing environment values.

## Architecture decision

Sell and maintain three **separate apps**: **Siloy Notes**, **Siloy Time**, and **Siloy Surface**. They share a brand standard and deployment checklist, but have independent app IDs, projects, data stores, update cadence, permission reviews and rollback paths. A bundle licence must not silently couple the apps.

### Preflight, before deploying anything

1. Confirm the approved account ID and name, Enterprise features and admin privileges. The dedicated credential should not be reused across customers.
2. Audit custom-object schema names, current IDs, properties, associations, and any name collisions. Never paste an object type ID from another HubSpot account.
3. Check app required scopes, user/record access rules, record editor permissions, version support, expected CRM objects and whether an app is already installed.
4. Confirm brand identity, customer-approved logo, Siloy licence and any licensed webfont hosting. For native HubSpot UI extensions use supported SDK controls, not injected CSS. Configure the colour palette and accessible labels through the design system.
5. Do not populate real/sensitive notes or timesheets as part of installation. Use synthetic UAT records and explicit permission tests.

### One-click SUKI reference install

GitHub Actions workflow: `.github/workflows/deploy-suki-suite.yml`, branch `codex/suki-suite-installer`.

It checks the SUKI credential, creates missing `siloy_note` and `siloy_time_entry` schemas, verifies their IDs, then independently builds, brands, tests, uploads, deploys and installs Notes and Time. App object references in source are rewritten *inside the build runner only* using that customer's resolved type ID. The old portal's numeric IDs are not reused. It fails if schemas, builds, installation or current required scopes cannot be verified. Run under a dedicated environment and log the GitHub run URL and resolved IDs at handover.

**Reference object IDs, November 2026 only:**

- Siloy Notes initial legacy object `siloy_note`: `2-256646328`
- Siloy Time initial legacy object `siloy_time_entry`: `2-256646413`

Source branches remain independent:
- `codex/corpus-note-hubspot-card`
- `codex/siloy-time-enterprise`

### Surface is not a native-only deployment

`Siloy_Surface_0.1.0.zip` is the working release source, including a HubSpot app (card, app page and settings) plus a Node/SQLite/OAuth service. Its native entry points call that external service. **Do not deploy with `https://surface.invalid` or represent a static preview as a functioning HubSpot integration.**

To complete Surface for SUKI:

1. Put the full release source into a versioned repository; preserve the Node service, tests, HubSpot project and frontend as one release.
2. Provision an HTTPS origin, persistent encrypted/backup-supported storage, secrets, allowed HubSpot portal, user policy and monitoring. Use separate OAuth and session encryption keys. The initial one-portal Node/SQLite implementation must not be represented as a shared multi-tenant service.
3. Configure the package with `npm run hubspot:configure -- https://<approved-origin>`, then test the bundle, deploy and install the HubSpot 2026.09 project to `149783010`.
4. Set app/client OAuth values in the host, complete an approved account-specific OAuth flow, verify signed launches, upload limits and per-user record grants.
5. Add the CRM card to Companies, Contacts, Deals and Tickets and test separate boards, four walls, saving, reload, permissions, attachment policy, history, rollback and task creation.
6. After UAT, consider a managed multi-tenant backend with tenant-isolated storage and deployment instead of one server per low-cost customer. Do not move data between tenant accounts or use unlicensed font files.

### Release gating and customer handover

| Gate | Notes | Time | Surface |
|---|---|---|---|
| HubSpot project deployed | Automated | Automated | Host and project still to deploy |
| Dedicated object storage | `siloy_note` | `siloy_time_entry` | SQLite in release; decide tenant-hosting architecture |
| App installed | CI verifies | CI verifies | OAuth + external service pending |
| Data create/load UAT | Required | Required | Required |
| Access/security review | Required | Required | Required |
| Record cards and permissions | Required | Required | Required |
| Backup/rollback | Required | Required | Required |

Record deliverables by customer and portal: product and source version, build/deploy ID, CRM object schema IDs, OAuth scopes, branding assets and permissions, implementation decisions, test evidence, known limitations, support owner and rollback procedure.

**Security warning:** An INTERNAL ONLY label is not access control. Current Notes and Time private-app functions have app-level tokens. Scope the record cards, CRM object permissions and access review appropriately, and enforce per-user authorization before advertising confidential-data guarantees.

**Commercial guidance:** The first two apps can be delivered per-portal through the current Projects workflow. Surface has a continuing hosting and data-storage cost, so a one-off low-price licence should specify that cost and responsibility explicitly.


## Mandatory record layout activation (not performed by project installation)

**HubSpot app installed != card visible.** Each app UI extension is registered only for the object types declared in its `*-hsmeta.json`. Add each card to the relevant record view in HubSpot. Customer-specific record layouts require an explicit activation and UAT step.

### Siloy Notes

- Intended record: **Company** (`companies`, middle-column `crm.record.tab`), with optional Company sidebar quick rail.
- Open any Company > **Customize** > edit the default record view > **Siloy Apps** tab > **Add card** > **Card library** > filter **App** > **Siloy Notes | Internal workspace** > **Add card** > **Save and exit**.
- Add the optional **Siloy Notes | Internal quick actions** sidebar card if authorised, and validate its visibility separately.

### Siloy Time

- Intended record: **Contact** (`contacts`, middle-column `crm.record.tab`). It does **not** appear on a Company just because the Company has a tab named **Siloy Apps**.
- Ensure at least one suitably authorised test Contact exists (create only when approved).
- Open a Contact > **Customize** > edit the default record view > create/select **Siloy Apps** tab > **Add card** > **Card library** > filter **App** > **Siloy Time | Weekly timesheet** > **Add card** > **Save and exit**.
- Reopen that Contact and verify the seven-day grid loads; create a sample Project if approved because new Time entries require an associated HubSpot Project.

### Siloy Surface

- Still not installed: its existing 0.1.1 branded package uses an external Node service, SQLite and OAuth; deploy the backend and complete tenant-specific OAuth before enabling cards or app pages. Never report a logo-only/placeholder card as a functional Surface installation.

### Acceptance criteria

- Record the exact target HubSpot portal ID, app installation success, deployed build ID, record type, card layout placement, test record URL, actual create/read UAT results and permissions review.
- A successful CI install job is **not** proof that the app card was added to the CRM layout or that a custom-object association works.
- For SUKI on 15 November 2026, both native apps were installed and schemas created. The reference portal had **0 Contact records** at the point of validation. Siloy Time therefore needed a Contact record and layout activation before it could appear.

## SUKI universal records and quick actions, 15 November 2026

The original CRM custom objects have no records and are preserved without deletion, but **the live app deployment must use these new, tested universal schemas**:

- Siloy Notes `siloy_note_multi`: `2-256648074` (Company, Contact, Deal, Ticket, Project associations)
- Siloy Time `siloy_time_entry_multi`: `2-256648076` (Company, Contact, Deal, Ticket, Project associations)

The independent app workflows and the one-click suite workflow resolve these names in SUKI, then replace old IDs **within the build workspace only**. The Time weekly timesheet remains a Contact tab and maintains its existing Project-required form. A new sidebar card `Siloy Time | Quick Log` works on Company, Contact, Deal and Ticket record pages: quick entry is associated with the current record and may optionally reference a Project. Both cards save to one Time object.

Siloy Notes' full workspace and quick capture sidebar apply to Company, Contact, Deal and Ticket record pages with association-aware backend calls. Original editor/decision/risk/follow-up features are preserved.

**Important layout step:** CRM > Companies > open a Company > Customize > Default view > right sidebar > Card library > App > add **Siloy Time | Quick Log**, and save. Repeat placement for Contacts, Deals and Tickets as desired; add Siloy Notes cards where relevant. A successful project installation alone never adds the card to customer views.

**UAT:** verify a saved quick log against a Company appears when reloading the Company sidebar. Verify the original timesheet still works on Contacts. Confirm Company, Contact, Deal, Ticket and Project association definitions in Data Model; do not represent a successful mocked unit test as live data-creation UAT.

**Security:** current static app tokens are app-level; the caller-supplied record IDs are not a substitute for user-level record authorization. Restrict internal rollout to authorised users and complete user-level access controls before selling confidentiality-sensitive use cases.
