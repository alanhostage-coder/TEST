# Siloy Revenue Intelligence - Action v0.3

Target: **Siloy UKI Apps**, HubSpot developer test portal **149783010**.

## Shipped source
HubSpot 2026.03 project, Deal sidebar card, app page, three app functions, pure deterministic scoring and thirteen automated tests. Six existing SRI Deal properties capture assessments only on explicit human Save. No AI credits, background CRM writes or production deployments.

## Build and deploy
On push to `codex/sri-action-hubspot`, `.github/workflows/sri-action-ship.yml` runs Node tests, validates the project and attempts upload/deploy/install using the existing SUKI HubSpot personal access key GitHub secret. The workflow targets **149783010** and does not change Notes or Time. Run `node --test tests/*.test.cjs` locally.

## Verification gates
Check GitHub Actions logs. Installation and current scopes are checked via HubSpot CLI. Verify the app card appears in a Deal sidebar, that the App Page loads, and that it handles an approved test Deal before treating end-to-end UAT as complete. If the key is not configured or CLI validation fails, the workflow must be treated as unsuccessful. No test Deal is seeded automatically.

## Deployment Studio
`studio/modules/revenue-intelligence-action.json` is a reusable module definition to incorporate into the standalone Deployment Studio pack generator. The existing 207 KB Studio HTML is not overwritten by this repository branch. Find and Insight remain roadmap modules, not enabled features.

## Security
Static private test app only. No secrets committed. Commercial rollouts need separate OAuth distribution, tenant configuration and install approval. Assessment does not create a task or send email.
