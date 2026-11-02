# Marketplace Training — web release

This release adds Marketplace Training to the existing web hub. Native iOS changes remain on the separate `codex/marketplace-training` branch; this web release contains no iOS project changes.

The feature uses versioned fictional vehicle records (`vehicles.mjs`), two locally hosted AI-generated illustrative photos, and a separate responsive customer chat. Customer openers use exact 70% availability / 15% offer / 15% vehicle-question thresholds. Server-authored profiles keep consistent motivations; casual/distracted customers may stop responding and have bounded follow-up opportunities. No real customer messages are sent.

`marketplace.mjs` isolates the private manager transcript from customer AI input. The AI selects relevant safe coaching; deterministic server rules alone approve/counter/decline actual recorded customer offers. Pricing cards apply only to vehicle selling price, excluding tax/title/fees. Employees cannot fabricate manager authorizations through their own messages. Tokens are AES-GCM protected, bound to an employee, and expire after six hours. Failed replies preserve drafts; failed saves expose a sealed save-only retry without grading again. A short per-instance cache deduplicates provider requests; the existing session UUID prevents duplicate history inserts.

The rubric is engagement 20, discovery 20, offers 20, management 15, trust 15 and progression 10. When no customer price offer occurs, offers/management are N/A and effective maxima are 31/31/0/0/23/15. The review explains weighting, shows exact verified salesperson quotes, reveals hidden motivation only after finishing, and includes coaching, manager history and the observed outcome. Appointment conversion and customer silence are not automatic penalties. AI judgments need review during the user's live pilot.

## Persistence and configuration

No migration or new environment variables. Existing `text_sessions` RLS ownership policies and employee JWTs are reused. New scenarios use `marketplace_<vehicle-id>` and complete review data lives in `scores._marketplace.review`; customer and private manager transcripts remain separate. The existing generic `marketplace` text/phone scenarios are preserved. New history has its own latest-30 query so it does not displace prior text/objection sessions. Existing server OpenAI settings and stable Objection/COOKIE session secret are reused; no keys are embedded in public code.

## Verification

Run `npm ci`, `npm run check`, and `npm test`. `node tests/preview.mjs` is a loopback-only synthetic preview with mocked providers, never a production entrypoint. The release is based on the current main voice hotfix and preserves its Phone/Text/Objection/auth behavior. The exact web-only release passed all 57 server/browser tests and syntax checks before publication. Automated checks cover opening weights, private prompt boundaries, authorization, quote validation, contextual weighting, silence/follow-up, retries, owner-scoped history, HTML escaping and auth-reset races.

The web release excludes the pending native iOS rebuild and its separate microphone-helper changes. Production deployment is authorized by Kyle's request to merge the feature into GitHub for web testing; Render's existing main auto-deploy setting publishes the merged commit. Native/TestFlight release remains a separate step. No production schema or secret changes are needed.
