# ObjectionIQ

Employee training with fictional customers: live Phone Training, Text Training, and Objection Lab. Employees sign in through Supabase Auth. Scores and reviews are saved to each employee's Supabase history.

## Objection Lab

Twelve objections: price, monthly payment, trade value, thinking it over, spouse/partner, competitor offers, credit, time, out-the-door pricing, down payment, interest rate, and warranty concerns. Choose English or Spanish, three difficulty levels, focused or progressive challenges, and independent or coached practice. Progressive customers can reveal connected concerns after the first concern has been explored.

The five-part rubric totals 100: acknowledge 15, discover 25, truthful relevant response 25, trust 15, appropriate next step 20. Reviews include transcript evidence, actionable coaching, a rewritten response, the concern behind the objection, and a suggested next drill. An appointment is not required when another next step better serves the customer.

Drills are typed. Customer replies and coaching use OpenAI; no real customer messages are sent. All backstories and deals are fictional. Employees should not enter real customer personal or financial data.

## Setup

1. Use Node.js 20 or later. Run `npm ci`.
2. Copy `.env.example` to `.env` and set your Supabase URL/publishable key, server-side OpenAI key, and a stable random `COOKIE_SECRET`. Never commit `.env`.
3. The existing Supabase tables `call_scores` and `text_sessions` must already be configured with RLS and employee ownership policies for SELECT and INSERT. Objection Lab reuses `text_sessions`: scenario starts with `objection_`, numeric dimensions live in `scores`, and detailed feedback is stored in `scores._review`. It does not require a schema migration for the existing production database.
4. Run `npm start` and visit `http://localhost:3000`. Create employee accounts through your normal Supabase administration process.

Use HTTPS in production and `NODE_ENV=production`. Render's standard `RENDER=true` environment enables the app's one-hop reverse-proxy setting. Existing Render environment variables are sufficient for this release. `OBJECTION_SESSION_SECRET` can override `COOKIE_SECRET`; use a stable secret shared by instances. Without either, drills expire after a server restart.

## Session and history behavior

Objection backstories and transcripts are protected in encrypted, authenticated tokens bound to the employee. The server grades its protected transcript; the browser cannot relabel a coached drill as independent. Tokens expire after six hours. In-progress drills stay in the current browser page's memory and are lost if the page is closed or refreshed. Finished reviews persist in Supabase. Signing out clears training state, and late responses from the old session are ignored.

There are 12 salesperson turns per objection drill. Reply failures retain the draft and conversation. Scoring failures can be retried; save failures preserve the review and offer a save-only retry. A session UUID prevents duplicate saved reviews. A short-lived in-memory cache deduplicates repeated AI requests within an instance; across restarts or multiple instances, repeated requests can still invoke the provider again, though the same saved review ID prevents duplicate database rows. Practice requests are limited per authenticated employee, with separate quotas for Objection Lab and legacy training. Independent/coached labels describe assistance provided by this app, not outside help.

## Verification

- `npm run check`: syntax checks for all application modules.
- `npm test`: service, HTTP route, and DOM regression tests with synthetic data and mocked external providers. No real credentials, employee data, or paid model calls are used.
- `node tests/preview.mjs`: local-only synthetic UI preview at `http://127.0.0.1:3417`. This is a development fixture, not the production entrypoint.

Phone calls require microphone permission and a live OpenAI Realtime connection. Model behavior and transcript accuracy vary. Pilot grading with a manager and compare the feedback against the actual conversation before using scores for employee evaluations.
