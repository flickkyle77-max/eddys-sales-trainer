# Eddy's Sales Call Trainer — private dealership MVP

A phone-friendly website with a live AI customer using OpenAI Realtime WebRTC, followed by AI scoring of a transcribed sales call. It includes eight call types, three difficulty levels, and local score history.

## Local setup

1. Install Node.js 20 or newer.
2. Run `npm install` in this folder.
3. Copy `.env.example` to `.env` and configure:
   - `OPENAI_API_KEY`: your API key from OpenAI Platform (separate API billing required).
   - `DEALERSHIP_PASSCODE`: a long code shared only with authorized team members.
   - `COOKIE_SECRET`: generate at least 32 random characters.
4. Run `npm start`.
5. Open `http://localhost:3000` on that same computer. Enter your name + dealership access code, select a scenario, allow the microphone, and begin talking.

## For coworkers on phones

Deploy the Node app on a host that supports HTTPS, such as Render, Railway, or a similar service. Set the environment variables on your host (do not publish your `.env` file). Set `NODE_ENV=production`. Use your secure HTTPS website URL on colleagues' phones. For iPhone, Safari's Share menu → Add to Home Screen.

**Security before broad distribution:** the shared-code login is a simple internal pilot, not full identity management. Use hosting-level access control or implement unique accounts, revocation, password reset, session management, audit logging, stricter spend limits, CSRF protection, and server-side rate limiting backed by a shared store before general production use. Restrict deployment to dealership staff. Do not submit real customer information in practice calls.

## What this version does / does not do

- Real phone-style microphone conversation: YES, when the OpenAI Realtime API connection works and API key has access to the configured model.
- Dynamic AI behavior per scenario and difficulty: YES.
- Transcript and AI scorecard: YES, provided the Realtime transcription events arrive with sufficient detail.
- Session scores saved in this browser only: YES.
- Manager dashboards, centralized reports, individual login credentials, and call recordings: NOT YET.
- API key stored in browser: NO. It remains on the server.
- Actual customer calls or real inventory/price lookup: NO. Simulated calls only.

## Notes

The application uses `/v1/realtime/calls` via server-side SDP exchange and `/v1/responses` to grade. Since realtime API configurations and event names can evolve, verify provider compatibility before rollout. The scoring model may make errors, and transcription can miss or mishear speech. Pilot with a few staff members and compare AI scoring against a human manager's evaluation.

The application never stores full transcripts on the server. Scoring sends the transcript to OpenAI and does not persist it in a dealership database. Browser localStorage holds score summaries only. The code has been syntax-checked but voice calling requires API credentials, a browser microphone, and network access to test end-to-end.
