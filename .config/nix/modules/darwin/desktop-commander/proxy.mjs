// mini-mcp proxy: Desktop Commander (stdio) → Streamable HTTP on loopback.
//
// Cloudflare Access sits in front (mini-mcp.jgoon.com, service tokens only);
// this proxy re-checks the Access JWT so a request that reached the port some
// other way is still refused, and exposes only an allowlist of DC's tools —
// set_config_value would let an agent clear its own limits.
//
// Installed inside the Desktop Commander package directory so the MCP SDK
// resolves from DC's bundled node_modules. Configured by environment (see
// default.nix); everything else in the environment passes through to DC.
import { createPublicKey, verify } from "node:crypto";
import { copyFileSync, chmodSync, mkdirSync } from "node:fs";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
  CallToolRequestSchema,
  CallToolResultSchema,
  ErrorCode,
  ListToolsRequestSchema,
  McpError,
} from "@modelcontextprotocol/sdk/types.js";

const env = process.env;
const port = Number(env.MINI_MCP_PORT);
const audience = env.MINI_MCP_ACCESS_AUD;
const teamDomain = env.MINI_MCP_ACCESS_TEAM_DOMAIN;
const allowedTools = new Set(env.MINI_MCP_ALLOWED_TOOLS.split(","));
const instructions = env.MINI_MCP_INSTRUCTIONS;
const toolTimeoutMs = 10 * 60 * 1000;
const maxBodyBytes = 4 * 1024 * 1024;

const log = (msg) => console.log(`${new Date().toISOString()} ${msg}`);

// DC rewrites its own config at runtime (and set_config_value would, if it
// were exposed); start every run from the nix-generated one.
const dcConfigDir = join(homedir(), ".claude-server-commander");
mkdirSync(dcConfigDir, { recursive: true });
copyFileSync(env.MINI_MCP_DC_CONFIG, join(dcConfigDir, "config.json"));
chmodSync(join(dcConfigDir, "config.json"), 0o600);

const childEnv = Object.fromEntries(
  Object.entries(env).filter(([k]) => !k.startsWith("MINI_MCP_")),
);
const upstream = new Client({ name: "mini-mcp-proxy", version: "1" });
upstream.onclose = () => {
  log("desktop commander exited; restarting via launchd");
  process.exit(1);
};
await upstream.connect(
  new StdioClientTransport({
    command: process.execPath,
    args: [join(dirname(fileURLToPath(import.meta.url)), "dist/index.js")],
    env: childEnv,
    stderr: "inherit",
  }),
);

// --- Cloudflare Access JWT (RS256, keys from the team's certs endpoint) ---
const issuer = `https://${teamDomain}`;
let keys = new Map();
let keysFetchedAt = 0;

async function signingKey(kid) {
  if (!keys.has(kid) && Date.now() - keysFetchedAt > 60_000) {
    keysFetchedAt = Date.now();
    const res = await fetch(`${issuer}/cdn-cgi/access/certs`);
    if (!res.ok) throw new Error(`certs fetch ${res.status}`);
    const { keys: jwks } = await res.json();
    keys = new Map(jwks.map((jwk) => [jwk.kid, createPublicKey({ key: jwk, format: "jwk" })]));
  }
  return keys.get(kid);
}

async function verifyAccessJwt(token) {
  const [h, p, s] = (token ?? "").split(".");
  if (!s) throw new Error("missing Access JWT");
  const header = JSON.parse(Buffer.from(h, "base64url"));
  if (header.alg !== "RS256") throw new Error(`alg ${header.alg}`);
  const key = await signingKey(header.kid);
  if (!key) throw new Error("unknown signing key");
  if (!verify("RSA-SHA256", Buffer.from(`${h}.${p}`), key, Buffer.from(s, "base64url"))) {
    throw new Error("bad signature");
  }
  const claims = JSON.parse(Buffer.from(p, "base64url"));
  const now = Date.now() / 1000;
  const auds = [].concat(claims.aud);
  if (!auds.includes(audience)) throw new Error("wrong audience");
  if (claims.iss !== issuer) throw new Error("wrong issuer");
  if (!(claims.exp > now) || (claims.nbf && claims.nbf > now + 60)) throw new Error("expired");
  return claims;
}

// --- MCP server: one stateless server per request, sharing the DC child ---
function mcpServer(caller) {
  const server = new Server(
    { name: "mini-mcp", version: "1" },
    { capabilities: { tools: {} }, instructions },
  );
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    const { tools } = await upstream.listTools();
    return { tools: tools.filter((t) => allowedTools.has(t.name)) };
  });
  server.setRequestHandler(CallToolRequestSchema, async (req) => {
    const { name, arguments: args } = req.params;
    if (!allowedTools.has(name)) {
      throw new McpError(ErrorCode.InvalidParams, `Unknown tool: ${name}`);
    }
    log(`${caller} ${name} ${JSON.stringify(args ?? {}).slice(0, 500)}`);
    return upstream.request(
      { method: "tools/call", params: req.params },
      CallToolResultSchema,
      { timeout: toolTimeoutMs },
    );
  });
  return server;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > maxBodyBytes) reject(new Error("body too large"));
      else chunks.push(c);
    });
    req.on("end", () => resolve(chunks.length ? JSON.parse(Buffer.concat(chunks)) : undefined));
    req.on("error", reject);
  });
}

function reply(res, status, text) {
  res.writeHead(status, { "content-type": "text/plain" }).end(text);
}

createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  if (path === "/healthz") return reply(res, 200, "ok\n");
  if (path !== "/mcp") return reply(res, 404, "not found\n");

  let claims;
  try {
    claims = await verifyAccessJwt(req.headers["cf-access-jwt-assertion"]);
  } catch (err) {
    log(`refused ${req.socket.remoteAddress}: ${err.message}`);
    return reply(res, 401, "unauthorized\n");
  }

  try {
    const body = req.method === "POST" ? await readBody(req) : undefined;
    const server = mcpServer(claims.common_name ?? claims.sub ?? "unknown");
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableJsonResponse: true,
    });
    res.on("close", () => {
      transport.close();
      server.close();
    });
    await server.connect(transport);
    await transport.handleRequest(req, res, body);
  } catch (err) {
    log(`error: ${err.message}`);
    if (!res.headersSent) reply(res, 400, "bad request\n");
  }
}).listen(port, "127.0.0.1", () => log(`listening on 127.0.0.1:${port}`));
