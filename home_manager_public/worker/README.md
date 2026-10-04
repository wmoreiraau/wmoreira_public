# Home Manager — Lookup Worker

A tiny Cloudflare Worker that proxies the "Look up" feature to Claude. It holds
the Anthropic API key server-side so it never ships inside the Flutter app.

## Endpoint

`POST /lookup` with `{ "title": "Clean shed" }` →

```json
{
  "summary": "…",
  "steps": ["…"],
  "shoppingList": [{ "item": "…", "reason": "…", "optional": false }],
  "safetyNote": "…"        // only present for risky tasks
}
```

Model: `claude-haiku-4-5`. The key is read from the `ANTHROPIC_API_KEY` secret.

## Deploy with Wrangler (needs Node.js)

```sh
npm install -D wrangler typescript @cloudflare/workers-types
npx wrangler login
npx wrangler deploy
npx wrangler secret put ANTHROPIC_API_KEY   # paste the key at the prompt
```

`wrangler deploy` prints the live URL: `https://home-manager-lookup.<subdomain>.workers.dev`

### Local testing

Create `.dev.vars` (copy `.dev.vars.example`) with your real key, then:

```sh
npx wrangler dev      # serves http://localhost:8787
```

## Deploy via the Cloudflare dashboard (no install)

Create a Worker in the dashboard, paste the logic from `src/index.ts`, and add
`ANTHROPIC_API_KEY` under Settings → Variables and Secrets (as a Secret).
