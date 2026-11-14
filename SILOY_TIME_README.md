# Siloy Time

**Standalone HubSpot-native timesheets**, independently licensed and deployed from Siloy Notes.

Product Update pilot portal: 145209388. The app uses the EXISTING (STT) Time Logs custom object 2-143515197 associated to Contacts and native Projects (0-970). It does not use the Siloy Notes object or functions.

Functions: Monday-Friday timesheets, previous/next navigation, 8h/40h utilisation cues, billable hours, project selection, editable entries, HubSpot persistence with associations, partial-save warning.

Brand: official logo from siloy.com/brand public identity detection and consistent Siloy pastel rail. Native HubSpot card styling does not permit arbitrary CSS.

Delivery: GitHub workflow uploads and installs a SEPARATE HubSpot Project siloy-time-enterprise. After workflow succeeds, add its App Card manually to the Contact layout (Customize > Add Card > Apps). Verify creation and editing with safe test data. Never claim installation or layout placement until confirmed.

Commercial release work still required: tenant object installer (current object ID is POC-only), per-user authorisation, licence management, approval workflow, data retention and audit, expanded QA, tenant configuration, App Marketplace security and distribution approval. Private app edition is not yet a public Marketplace listing.
