export interface Env {
  ANTHROPIC_API_KEY: string;
  // Full JSON of a Firebase service-account key. While absent, /lookup and
  // /maintenance stay open (legacy mode) and /join + /leave return 503. Once
  // set, all endpoints require a signed-in Firebase user; lookups also verify
  // home membership (defense in depth).
  FIREBASE_SERVICE_ACCOUNT?: string;
  // Optional: set to your app's origin (e.g. https://yourapp.pages.dev) to lock
  // down CORS later. Defaults to "*" so it works during development.
  ALLOWED_ORIGIN?: string;
}

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const MODEL = "claude-haiku-4-5";
const MAX_TOKENS = 2000;

const RECURRENCE_OPTIONS = ["Weekly", "Monthly", "Quarterly", "Every 6 Months", "Yearly"];

const SHOPPING_LIST_SCHEMA = {
  type: "array",
  items: {
    type: "object",
    additionalProperties: false,
    properties: {
      item: { type: "string" },
      reason: { type: "string" },
      optional: { type: "boolean" },
    },
    required: ["item", "reason", "optional"],
  },
};

const SUGGESTED_RECURRENCES_SCHEMA = {
  type: "array",
  items: {
    type: "object",
    additionalProperties: false,
    properties: {
      recurrence: { type: "string", enum: RECURRENCE_OPTIONS },
      description: { type: "string" },
    },
    required: ["recurrence", "description"],
  },
};

const SYSTEM_PROMPT = `You are a practical home-maintenance assistant inside a home task-tracking app.
Given a single household task or issue (optionally with the manufacturer and model of the equipment involved), produce:
- summary: 1-3 plain-language sentences on how to approach fixing it. If the task is recurring, mention how often each action should happen.
- steps: clear, ordered, practical steps a typical homeowner can follow.
- shoppingList: the materials and tools needed; give each a short reason and set "optional" to true for nice-to-haves.
- isRecurrent: true if this task is recurring by nature and should repeat on a schedule (e.g. cleaning gutters, watering plants, servicing a lawn mower); false for one-off fixes.
- involvesEquipment: true if the task involves an appliance or piece of equipment that needs recurring maintenance (e.g. lawn mower, dishwasher, HVAC unit).
- itemName: when isRecurrent or involvesEquipment is true, the appliance or item that needs the recurring maintenance, as a short noun phrase WITHOUT the action verb (e.g. "Oven" for "Clean oven", "Gutters" for "Clean gutters", "Lawn mower" for "Lawn mower service"). Otherwise an empty string.
- suggestedRecurrences: when isRecurrent is true, one entry for EACH distinct cadence mentioned in the summary (1-4 entries), each with recurrence (exactly one of "Weekly", "Monthly", "Quarterly", "Every 6 Months", "Yearly"; pick the closest) and description (a short action label of at most 5 words). When isRecurrent is false, return an empty array.
Keep everything concise and realistic. Include a safetyNote ONLY when the task involves electricity, gas, working at height, or hazardous chemicals.
If the input is not a genuine home task or issue, put a brief note in summary saying so and return empty steps and shoppingList.`;

const RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary: { type: "string" },
    steps: { type: "array", items: { type: "string" } },
    shoppingList: SHOPPING_LIST_SCHEMA,
    safetyNote: { type: "string" },
    isRecurrent: { type: "boolean" },
    involvesEquipment: { type: "boolean" },
    itemName: { type: "string" },
    suggestedRecurrences: SUGGESTED_RECURRENCES_SCHEMA,
  },
  required: [
    "summary",
    "steps",
    "shoppingList",
    "isRecurrent",
    "involvesEquipment",
    "itemName",
    "suggestedRecurrences",
  ],
};

const MAINTENANCE_SYSTEM_PROMPT = `You are a practical maintenance assistant inside a home task-tracking app.
Given a recurring maintenance task (an appliance, equipment, or any recurring household chore such as watering plants or cleaning gutters; optionally with a manufacturer, model, and extra notes such as a plant type), produce JSON with:
- summary: 2-4 plain-language sentences describing the recommended routine maintenance, tailored to any notes provided. Mention how often each maintenance action should happen.
- suggestedRecurrences: one entry for EACH distinct cadence mentioned in summary (1-4 entries). Each entry has:
  - recurrence: exactly one of "Weekly", "Monthly", "Quarterly", "Every 6 Months", "Yearly" (pick the closest).
  - description: a short action label of at most 5 words, e.g. "Test alarm button", "Replace battery".
  Example for a smoke alarm: Monthly "Test alarm button", Every 6 Months "Vacuum dust from vents", Yearly "Replace battery".
- suggestedRecurrence: the recurrence of the single most important entry (kept for older app versions).
- shoppingList: the materials and tools needed for the routine maintenance; give each a short reason and set "optional" to true for nice-to-haves. Return an empty array if nothing is needed.
- manufacturerDomain: the manufacturer's official registrable domain only, lowercase, with no scheme, path, or "www." (e.g. "lg.com", "bosch-home.com"). If no specific manufacturer is given or you are unsure, use an empty string.
- link: a single official URL whose domain is manufacturerDomain - prefer the product's support/manual/downloads page; otherwise the product's details page. If you are not confident a real, official URL exists, use an empty string. Never invent URLs.
- linkType: "manual" if link is a manual/support/downloads page, otherwise "details".
If manufacturer or model is missing, give a sensible general maintenance plan for the task and set manufacturerDomain and link to empty strings.`;

const MAINTENANCE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary: { type: "string" },
    suggestedRecurrences: SUGGESTED_RECURRENCES_SCHEMA,
    suggestedRecurrence: { type: "string", enum: RECURRENCE_OPTIONS },
    shoppingList: SHOPPING_LIST_SCHEMA,
    manufacturerDomain: { type: "string" },
    link: { type: "string" },
    linkType: { type: "string", enum: ["manual", "details"] },
  },
  required: [
    "summary",
    "suggestedRecurrences",
    "suggestedRecurrence",
    "shoppingList",
    "manufacturerDomain",
    "link",
    "linkType",
  ],
};

// Keeps only well-formed entries with a known recurrence, capped at 6.
function sanitizeSuggestions(raw: unknown): Array<{ recurrence: string; description: string }> {
  if (!Array.isArray(raw)) {
    return [];
  }
  const out: Array<{ recurrence: string; description: string }> = [];
  for (const entry of raw) {
    if (out.length >= 6) {
      break;
    }
    if (typeof entry !== "object" || entry === null) {
      continue;
    }
    const rec = (entry as { recurrence?: unknown }).recurrence;
    if (typeof rec !== "string" || !RECURRENCE_OPTIONS.includes(rec)) {
      continue;
    }
    const desc = (entry as { description?: unknown }).description;
    out.push({
      recurrence: rec,
      description: typeof desc === "string" ? desc.trim().slice(0, 80) : "",
    });
  }
  return out;
}

// A small subset of multi-label public suffixes so we can derive the
// registrable domain (eTLD+1) without shipping the full Public Suffix List.
const TWO_LEVEL_TLDS = new Set<string>([
  "co.uk", "org.uk", "me.uk", "ac.uk", "gov.uk", "ltd.uk", "plc.uk",
  "co.jp", "or.jp", "ne.jp", "com.au", "net.au", "org.au", "co.nz",
  "co.in", "co.za", "com.br", "com.mx", "com.tr", "com.cn", "com.sg",
  "co.kr", "com.hk", "com.tw",
]);

function registrableDomain(host: string): string {
  const parts = host.split(".").filter(Boolean);
  if (parts.length <= 2) {
    return parts.join(".");
  }
  const lastTwo = parts.slice(-2).join(".");
  if (TWO_LEVEL_TLDS.has(lastTwo)) {
    return parts.slice(-3).join(".");
  }
  return lastTwo;
}

function normalizeDomain(domain: unknown): string {
  return String(domain || "")
    .toLowerCase()
    .trim()
    .replace(/^https?:\/\//, "")
    .replace(/^www\./, "")
    .split("/")[0]
    .replace(/\.+$/, "");
}

// Returns true only if the URL returns HTTP 200 (following redirects).
async function reachable(urlStr: string): Promise<boolean> {
  for (const method of ["HEAD", "GET"]) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 6000);
      const res = await fetch(urlStr, {
        method,
        redirect: "follow",
        signal: controller.signal,
        headers: { "User-Agent": "HomeManagerBot/1.0 (+maintenance link check)" },
      });
      clearTimeout(timer);
      if (res.status === 200) {
        return true;
      }
      // Some servers reject HEAD; retry once with GET on method-related errors.
      if (method === "HEAD" && (res.status === 405 || res.status === 403 || res.status === 501)) {
        continue;
      }
      return false;
    } catch {
      // Try the next method (e.g. HEAD aborted/unsupported), then give up.
    }
  }
  return false;
}

// Mandatory validation: never trust the model's URL.
//  (a) the URL's registrable domain must EXACTLY equal the manufacturer domain
//      (registrable-domain comparison, not a substring -> rejects lg.com.evil.example)
//  (b) the URL must be HTTPS and return HTTP 200.
// Returns the URL only if both checks pass, otherwise null.
async function validateLink(candidate: unknown, domain: string): Promise<string | null> {
  if (typeof candidate !== "string" || !candidate || !domain) {
    return null;
  }
  let parsed: URL;
  try {
    parsed = new URL(candidate);
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:") {
    return null;
  }
  const host = parsed.hostname.toLowerCase().replace(/\.+$/, "");
  const cleanDomain = normalizeDomain(domain);
  if (!cleanDomain || registrableDomain(host) !== registrableDomain(cleanDomain)) {
    return null;
  }
  const ok = await reachable(candidate);
  return ok ? candidate : null;
}

function cors(env: Env): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": env.ALLOWED_ORIGIN || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
  };
}

function json(body: unknown, status: number, env: Env): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...cors(env) },
  });
}

// ---------------------------------------------------------------------------
// Firebase: ID-token verification + Firestore REST via a service account.
// ---------------------------------------------------------------------------

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

type FirebaseUser = {
  uid: string;
  name: string;
  picture: string;
  email: string;
};

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function b64urlToBytes(s: string): Uint8Array {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  return b64ToBytes(s);
}

function bytesToB64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function parseServiceAccount(env: Env): ServiceAccount | null {
  if (!env.FIREBASE_SERVICE_ACCOUNT) return null;
  try {
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT) as ServiceAccount;
    return sa && sa.client_email && sa.private_key && sa.project_id ? sa : null;
  } catch {
    return null;
  }
}

let jwksCache: Array<Record<string, string>> | null = null;
let jwksExpiry = 0;

async function getGoogleJwks(): Promise<Array<Record<string, string>>> {
  if (jwksCache && Date.now() < jwksExpiry) return jwksCache;
  const res = await fetch(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  );
  if (!res.ok) throw new Error("jwks fetch failed");
  const data = (await res.json()) as { keys?: Array<Record<string, string>> };
  jwksCache = data.keys || [];
  jwksExpiry = Date.now() + 3600 * 1000;
  return jwksCache;
}

// Verifies a Firebase Auth ID token (RS256) and returns the caller identity,
// or null when invalid/expired/for another project.
async function verifyIdToken(
  idToken: string,
  projectId: string,
): Promise<FirebaseUser | null> {
  try {
    const parts = idToken.split(".");
    if (parts.length !== 3) return null;
    const header = JSON.parse(
      new TextDecoder().decode(b64urlToBytes(parts[0])),
    ) as { kid?: string };
    const payload = JSON.parse(
      new TextDecoder().decode(b64urlToBytes(parts[1])),
    ) as Record<string, unknown>;
    const now = Date.now() / 1000;
    if (payload.aud !== projectId) return null;
    if (payload.iss !== `https://securetoken.google.com/${projectId}`) return null;
    if (!(typeof payload.exp === "number" && payload.exp > now)) return null;
    if (typeof payload.sub !== "string" || payload.sub.length === 0) return null;
    const keys = await getGoogleJwks();
    const jwk = keys.find((k) => k.kid === header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const ok = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      key,
      b64urlToBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
    if (!ok) return null;
    return {
      uid: payload.sub,
      name: typeof payload.name === "string" ? payload.name : "",
      picture: typeof payload.picture === "string" ? payload.picture : "",
      email: typeof payload.email === "string" ? payload.email : "",
    };
  } catch {
    return null;
  }
}

async function getBearerUser(
  request: Request,
  sa: ServiceAccount,
): Promise<FirebaseUser | null> {
  const header = request.headers.get("Authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/);
  if (!match) return null;
  return verifyIdToken(match[1], sa.project_id);
}

let saTokenCache: string | null = null;
let saTokenExpiry = 0;

// OAuth access token for Firestore REST, minted from the service-account key.
async function getAccessToken(sa: ServiceAccount): Promise<string> {
  if (saTokenCache && Date.now() < saTokenExpiry) return saTokenCache;
  const iat = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const header = bytesToB64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = bytesToB64url(
    enc.encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/datastore",
        aud: "https://oauth2.googleapis.com/token",
        iat,
        exp: iat + 3600,
      }),
    ),
  );
  const unsigned = `${header}.${claims}`;
  const pem = sa.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    b64ToBytes(pem).buffer as ArrayBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(unsigned)),
  );
  const jwt = `${unsigned}.${bytesToB64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=${encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer")}&assertion=${jwt}`,
  });
  if (!res.ok) throw new Error("token exchange failed");
  const data = (await res.json()) as { access_token: string; expires_in: number };
  saTokenCache = data.access_token;
  saTokenExpiry = Date.now() + (data.expires_in - 300) * 1000;
  return saTokenCache;
}

function docsBase(sa: ServiceAccount): string {
  return `projects/${sa.project_id}/databases/(default)/documents`;
}

async function fsFetch(
  sa: ServiceAccount,
  path: string,
  init?: RequestInit,
): Promise<Response> {
  const token = await getAccessToken(sa);
  return fetch(`https://firestore.googleapis.com/v1/${path}`, {
    ...(init || {}),
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });
}

type FsDocument = { name: string; fields?: Record<string, unknown> };

async function fsGetDoc(
  sa: ServiceAccount,
  relPath: string,
): Promise<FsDocument | null> {
  const res = await fsFetch(sa, `${docsBase(sa)}/${relPath}`);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error("firestore get failed");
  return (await res.json()) as FsDocument;
}

async function fsFindHomeByCode(
  sa: ServiceAccount,
  code: string,
): Promise<FsDocument | null> {
  const res = await fsFetch(sa, `${docsBase(sa)}:runQuery`, {
    method: "POST",
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: "homes" }],
        where: {
          fieldFilter: {
            field: { fieldPath: "inviteCode" },
            op: "EQUAL",
            value: { stringValue: code },
          },
        },
        limit: 1,
      },
    }),
  });
  if (!res.ok) throw new Error("firestore query failed");
  const rows = (await res.json()) as Array<{ document?: FsDocument }>;
  for (const row of rows) if (row.document) return row.document;
  return null;
}

async function fsCommit(sa: ServiceAccount, writes: unknown[]): Promise<void> {
  const res = await fsFetch(sa, `${docsBase(sa)}:commit`, {
    method: "POST",
    body: JSON.stringify({ writes }),
  });
  if (!res.ok) throw new Error("firestore commit failed");
}

const sv = (s: string) => ({ stringValue: s });

// Decodes a Firestore REST value into plain JS (only the types we use).
function decodeValue(v: unknown): unknown {
  if (!v || typeof v !== "object") return null;
  const value = v as Record<string, unknown>;
  if ("stringValue" in value) return value.stringValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("arrayValue" in value) {
    const arr = value.arrayValue as { values?: unknown[] };
    return (arr.values || []).map(decodeValue);
  }
  if ("mapValue" in value) {
    const out: Record<string, unknown> = {};
    const fields = (value.mapValue as { fields?: Record<string, unknown> }).fields || {};
    for (const k in fields) out[k] = decodeValue(fields[k]);
    return out;
  }
  return null;
}

async function isHomeMember(
  sa: ServiceAccount,
  homeId: string,
  uid: string,
): Promise<boolean> {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(homeId)) return false;
  const doc = await fsGetDoc(sa, `homes/${homeId}`);
  if (!doc) return false;
  const memberIds = decodeValue(doc.fields && doc.fields.memberIds);
  return Array.isArray(memberIds) && memberIds.includes(uid);
}

// Defense in depth for the AI endpoints: once the service account is
// configured, callers must be signed in AND a member of the home they name.
// Returns an error Response, or null to continue.
async function enforceLookupAuth(
  request: Request,
  env: Env,
  body: { homeId?: unknown },
): Promise<Response | null> {
  const sa = parseServiceAccount(env);
  if (!sa) return null; // secret not set yet -> legacy open mode
  const user = await getBearerUser(request, sa);
  if (!user) return json({ error: "Sign in to use the lookup." }, 401, env);
  const homeId = typeof body.homeId === "string" ? body.homeId : "";
  let member = false;
  try {
    member = homeId ? await isHomeMember(sa, homeId, user.uid) : false;
  } catch {
    return json({ error: "Server error verifying membership." }, 502, env);
  }
  if (!member) return json({ error: "Not a member of this home." }, 403, env);
  return null;
}

function randomDocId(): string {
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const arr = new Uint8Array(20);
  crypto.getRandomValues(arr);
  let id = "";
  for (const b of arr) id += chars[b % chars.length];
  return id;
}

function generateInviteCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const arr = new Uint8Array(6);
  crypto.getRandomValues(arr);
  let code = "";
  for (const b of arr) code += chars[b % chars.length];
  return code;
}

// POST /join {code}: validates the invite code and performs the membership
// writes with the Admin credentials, so clients can never forge memberIds.
async function handleJoin(request: Request, env: Env): Promise<Response> {
  const sa = parseServiceAccount(env);
  if (!sa) {
    return json(
      { error: "Sharing is not configured on the server (missing FIREBASE_SERVICE_ACCOUNT)." },
      503,
      env,
    );
  }
  const user = await getBearerUser(request, sa);
  if (!user) return json({ error: "Sign in to join a home." }, 401, env);

  let body: { code?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "Body must be JSON" }, 400, env);
  }
  const code = (typeof body.code === "string" ? body.code : "").trim().toUpperCase();
  if (!/^[A-Z2-9]{6}$/.test(code)) {
    return json({ error: "Invalid invite code." }, 400, env);
  }

  let homeDoc: FsDocument | null;
  try {
    homeDoc = await fsFindHomeByCode(sa, code);
  } catch {
    return json({ error: "Server error looking up the code." }, 502, env);
  }
  if (!homeDoc) return json({ error: "No home found for that code." }, 404, env);

  const homeId = homeDoc.name.split("/").pop() as string;
  const homeName = (decodeValue(homeDoc.fields && homeDoc.fields.name) as string) || "";
  const memberIds =
    (decodeValue(homeDoc.fields && homeDoc.fields.memberIds) as string[]) || [];

  const writes: unknown[] = [];
  if (!memberIds.includes(user.uid)) {
    writes.push({
      update: {
        name: homeDoc.name,
        fields: {
          members: {
            mapValue: {
              fields: {
                [user.uid]: {
                  mapValue: {
                    fields: {
                      displayName: sv(user.name),
                      photoUrl: sv(user.picture),
                      role: sv("member"),
                    },
                  },
                },
              },
            },
          },
        },
      },
      updateMask: { fieldPaths: ["members.`" + user.uid + "`"] },
      updateTransforms: [
        { fieldPath: "memberIds", appendMissingElements: { values: [sv(user.uid)] } },
        { fieldPath: "members.`" + user.uid + "`.joinedAt", setToServerValue: "REQUEST_TIME" },
      ],
      currentDocument: { exists: true },
    });
  }
  writes.push({
    update: {
      name: `${docsBase(sa)}/users/${user.uid}`,
      fields: { homeId: sv(homeId) },
    },
    updateMask: { fieldPaths: ["homeId"] },
  });

  try {
    await fsCommit(sa, writes);
  } catch {
    return json({ error: "Could not join the home. Try again." }, 502, env);
  }
  return json({ homeId, homeName }, 200, env);
}

// POST /leave: removes the caller from their current home and creates a
// fresh personal home for them.
async function handleLeave(request: Request, env: Env): Promise<Response> {
  const sa = parseServiceAccount(env);
  if (!sa) {
    return json(
      { error: "Sharing is not configured on the server (missing FIREBASE_SERVICE_ACCOUNT)." },
      503,
      env,
    );
  }
  const user = await getBearerUser(request, sa);
  if (!user) return json({ error: "Sign in first." }, 401, env);

  let homeDoc: FsDocument | null;
  try {
    const userDoc = await fsGetDoc(sa, `users/${user.uid}`);
    const homeId = userDoc
      ? (decodeValue(userDoc.fields && userDoc.fields.homeId) as string | null)
      : null;
    if (!homeId) return json({ error: "No home to leave." }, 400, env);
    homeDoc = await fsGetDoc(sa, `homes/${homeId}`);
    if (!homeDoc) return json({ error: "Home not found." }, 404, env);
  } catch {
    return json({ error: "Server error reading your home." }, 502, env);
  }

  const memberIds =
    (decodeValue(homeDoc.fields && homeDoc.fields.memberIds) as string[]) || [];
  if (!memberIds.includes(user.uid)) {
    return json({ error: "You are not a member of this home." }, 403, env);
  }
  if (memberIds.length <= 1) {
    return json(
      { error: "You are the only member of this home — nothing to leave." },
      400,
      env,
    );
  }

  const newHomeId = randomDocId();
  const displayName = user.name || "";
  const writes: unknown[] = [
    {
      update: { name: homeDoc.name, fields: {} },
      updateMask: { fieldPaths: ["members.`" + user.uid + "`"] },
      updateTransforms: [
        { fieldPath: "memberIds", removeAllFromArray: { values: [sv(user.uid)] } },
      ],
      currentDocument: { exists: true },
    },
    {
      update: {
        name: `${docsBase(sa)}/homes/${newHomeId}`,
        fields: {
          name: sv(displayName ? `${displayName}'s Home` : "My Home"),
          ownerId: sv(user.uid),
          inviteCode: sv(generateInviteCode()),
          memberIds: { arrayValue: { values: [sv(user.uid)] } },
          members: {
            mapValue: {
              fields: {
                [user.uid]: {
                  mapValue: {
                    fields: {
                      displayName: sv(displayName),
                      photoUrl: sv(user.picture),
                      role: sv("owner"),
                    },
                  },
                },
              },
            },
          },
        },
      },
      updateTransforms: [
        { fieldPath: "createdAt", setToServerValue: "REQUEST_TIME" },
        { fieldPath: "members.`" + user.uid + "`.joinedAt", setToServerValue: "REQUEST_TIME" },
      ],
      currentDocument: { exists: false },
    },
    {
      update: {
        name: `${docsBase(sa)}/users/${user.uid}`,
        fields: { homeId: sv(newHomeId) },
      },
      updateMask: { fieldPaths: ["homeId"] },
    },
  ];

  try {
    await fsCommit(sa, writes);
  } catch {
    return json({ error: "Could not leave the home. Try again." }, 502, env);
  }
  return json({ homeId: newHomeId }, 200, env);
}

type ClaudeOutcome =
  | { result: Record<string, unknown>; error?: undefined }
  | { error: Response; result?: undefined };

// Calls Claude with structured-output JSON and returns { result } or { error }.
async function callClaude(
  env: Env,
  system: string,
  schema: unknown,
  userContent: string,
): Promise<ClaudeOutcome> {
  let upstream: Response;
  try {
    upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system,
        messages: [{ role: "user", content: userContent }],
        output_config: { format: { type: "json_schema", schema } },
      }),
    });
  } catch {
    return { error: json({ error: "Could not reach Claude" }, 502, env) };
  }

  if (!upstream.ok) {
    const detail = await upstream.text();
    return {
      error: json({ error: "Claude request failed", status: upstream.status, detail }, 502, env),
    };
  }

  const data = (await upstream.json()) as {
    content?: Array<{ type: string; text?: string }>;
    stop_reason?: string;
  };

  if (data.stop_reason === "refusal") {
    return { error: json({ error: "Claude declined this request" }, 422, env) };
  }
  if (data.stop_reason === "max_tokens") {
    return { error: json({ error: "Response was too long; try again" }, 502, env) };
  }

  const text = data.content?.find((b) => b.type === "text")?.text;
  if (!text) {
    return { error: json({ error: "Empty response from Claude" }, 502, env) };
  }

  try {
    return { result: JSON.parse(text) as Record<string, unknown> };
  } catch {
    return { error: json({ error: "Could not parse Claude output" }, 502, env) };
  }
}

async function handleLookup(request: Request, env: Env): Promise<Response> {
  let body: {
    title?: unknown;
    manufacturer?: unknown;
    model?: unknown;
    homeId?: unknown;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "Body must be JSON" }, 400, env);
  }

  const title = body.title;
  if (typeof title !== "string" || title.trim().length === 0) {
    return json({ error: "Provide a non-empty 'title'" }, 400, env);
  }
  const authError = await enforceLookupAuth(request, env, body);
  if (authError) return authError;
  const cleanTitle = title.trim().slice(0, 200);
  const manufacturer = typeof body.manufacturer === "string" ? body.manufacturer.trim() : "";
  const model = typeof body.model === "string" ? body.model.trim() : "";

  const detailParts: string[] = [];
  if (manufacturer) detailParts.push(`Manufacturer: ${manufacturer.slice(0, 80)}`);
  if (model) detailParts.push(`Model: ${model.slice(0, 80)}`);
  const detail = detailParts.length ? ` (${detailParts.join(", ")})` : "";
  const userContent = `${cleanTitle}${detail}`;

  const out = await callClaude(env, SYSTEM_PROMPT, RESULT_SCHEMA, userContent);
  if (out.error) {
    return out.error;
  }

  const result = out.result;
  const isRecurrent = result.isRecurrent === true;
  const payload = {
    summary: typeof result.summary === "string" ? result.summary : "",
    steps: Array.isArray(result.steps) ? result.steps : [],
    shoppingList: Array.isArray(result.shoppingList) ? result.shoppingList : [],
    safetyNote: typeof result.safetyNote === "string" ? result.safetyNote : "",
    isRecurrent,
    involvesEquipment: result.involvesEquipment === true,
    itemName: typeof result.itemName === "string" ? result.itemName.trim().slice(0, 60) : "",
    suggestedRecurrences: isRecurrent ? sanitizeSuggestions(result.suggestedRecurrences) : [],
  };
  return json(payload, 200, env);
}

async function handleMaintenance(request: Request, env: Env): Promise<Response> {
  let body: {
    appliance?: unknown;
    manufacturer?: unknown;
    model?: unknown;
    notes?: unknown;
    homeId?: unknown;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "Body must be JSON" }, 400, env);
  }

  const appliance = typeof body.appliance === "string" ? body.appliance.trim() : "";
  const manufacturer = typeof body.manufacturer === "string" ? body.manufacturer.trim() : "";
  const model = typeof body.model === "string" ? body.model.trim() : "";
  const notes = typeof body.notes === "string" ? body.notes.trim() : "";

  if (appliance.length === 0) {
    return json({ error: "Provide a non-empty 'appliance'" }, 400, env);
  }
  const authError = await enforceLookupAuth(request, env, body);
  if (authError) return authError;

  const detailParts: string[] = [];
  if (manufacturer) detailParts.push(`Manufacturer: ${manufacturer.slice(0, 80)}`);
  if (model) detailParts.push(`Model: ${model.slice(0, 80)}`);
  const detail = detailParts.length ? ` (${detailParts.join(", ")})` : "";
  const notesPart = notes ? `. Notes: ${notes.slice(0, 300)}` : "";
  const userContent = `Task: ${appliance.slice(0, 120)}${detail}${notesPart}`;

  const out = await callClaude(
    env,
    MAINTENANCE_SYSTEM_PROMPT,
    MAINTENANCE_SCHEMA,
    userContent,
  );
  if (out.error) {
    return out.error;
  }

  const result = out.result;
  const manufacturerDomain = normalizeDomain(result.manufacturerDomain);
  // Validate the model's URL before ever returning it to the app.
  const validatedLink = await validateLink(result.link, manufacturerDomain);

  const suggestions = sanitizeSuggestions(result.suggestedRecurrences);
  let primary =
    typeof result.suggestedRecurrence === "string" &&
    RECURRENCE_OPTIONS.includes(result.suggestedRecurrence)
      ? result.suggestedRecurrence
      : "";
  if (!primary) {
    primary = suggestions.length > 0 ? suggestions[0].recurrence : "Monthly";
  }
  if (suggestions.length === 0) {
    suggestions.push({ recurrence: primary, description: "" });
  }

  const payload = {
    summary: typeof result.summary === "string" ? result.summary : "",
    suggestedRecurrence: primary,
    suggestedRecurrences: suggestions,
    shoppingList: Array.isArray(result.shoppingList) ? result.shoppingList : [],
    manufacturerDomain,
    link: validatedLink || "",
    linkType: result.linkType === "manual" ? "manual" : "details",
  };
  return json(payload, 200, env);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors(env) });
    }

    if (request.method === "GET" && url.pathname === "/") {
      return new Response(
        "Home Manager lookup worker is running. POST /lookup or /maintenance.",
        { status: 200, headers: cors(env) },
      );
    }

    if (request.method !== "POST") {
      return json({ error: "Not found" }, 404, env);
    }

    if (url.pathname === "/join") {
      return handleJoin(request, env);
    }
    if (url.pathname === "/leave") {
      return handleLeave(request, env);
    }

    if (!env.ANTHROPIC_API_KEY) {
      return json({ error: "Server is missing ANTHROPIC_API_KEY" }, 500, env);
    }

    if (url.pathname === "/lookup") {
      return handleLookup(request, env);
    }
    if (url.pathname === "/maintenance") {
      return handleMaintenance(request, env);
    }
    return json({ error: "Not found" }, 404, env);
  },
};
