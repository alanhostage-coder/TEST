# Codex deployment brief

Target HubSpot account: Product Updates, 145209388.

Use the existing `Corpus Notes` object `2-256491528` (`p145209388_corpus_notes`) with the existing Company association. Do not recreate or modify the object schema.

HubSpot Projects 2026.03: deploy the modern CRM tab UI extension `corpus_note_company_card` and app function `corpus_notes_api`. Never write to meeting descriptions, attendee information, invitations or email. The meeting activity ID is a text reference only.

Run `node --test tests/corpus-notes.test.js` and `hs project install-deps`, then `hs project upload --account 145209388`. Inspect build, deploy, install app and place card on Company view. Do not claim the card is live unless installation and Company-record layout placement are verified.

The app token is account scoped; audit permissions before storing confidential data. Never check in a personal access key.
