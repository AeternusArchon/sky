# Cloudflare Tunnel + Zero Trust Access

**Task 0.5.** Gets `sky.overlordlabs.net` reachable from your phone on cellular, with no port forwarding and no listening surface on your router.

> **Do this last in Phase 0.** Bring the stack up and verify it on the LAN first. Debugging a tunnel that points at a service which was never healthy wastes an evening.

---

## The shape of it

```
iPhone (cellular) → Cloudflare edge → Access policy → tunnel → gateway:8080
                                          ↑
                              identity check happens HERE,
                              before anything reaches your house
```

The connection is **outbound-only**. `cloudflared` dials out to Cloudflare and holds the connection open. Nothing on your network listens for inbound traffic, so there is nothing on your perimeter to scan or exploit. See DL-004.

---

## Steps

### 1. Create the tunnel

Cloudflare dashboard → **Zero Trust** → **Networks** → **Tunnels** → *Create a tunnel* → **Cloudflared**.

Name it `sky-node`. Cloudflare hands you a token — a long opaque string.

### 2. Store the token

```bash
# In /srv/sky/.env
CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoi...
```

⚠️ **Tier 0.** This token is enough for anyone holding it to impersonate your tunnel. `.env` stays mode `600` and never enters the repo.

### 3. Route the hostname

Still in the tunnel config → **Public Hostnames** → *Add a public hostname*:

| Field | Value |
|---|---|
| Subdomain | `sky` |
| Domain | `overlordlabs.net` |
| Service type | `HTTP` |
| URL | `gateway:8080` |

`gateway` resolves because `cloudflared` runs on the `sky` Docker network alongside it. If you install `cloudflared` on the host instead of in Compose, use `http://localhost:8080`.

### 4. Gate it with Access — do not skip this

**Zero Trust → Access → Applications → Add an application → Self-hosted.**

| Field | Value |
|---|---|
| Application domain | `sky.overlordlabs.net` |
| Session duration | 30 days (it's your own device) |
| Policy | *Allow* → **Emails** → your address |

Without this step the tunnel publishes your assistant to the open internet. The tunnel solves *reachability*. Access solves *authorization*. They are different problems and you need both.

### 5. Start it

```bash
docker compose --profile tunnel up -d
docker compose logs -f cloudflared     # look for "Registered tunnel connection"
```

### 6. Verify — the actual Phase 0 test

On your iPhone: **turn Wi-Fi off.** On cellular, open `https://sky.overlordlabs.net`.

You should get a Cloudflare Access login, then **"Sky is online."**

Wi-Fi off matters. On Wi-Fi you may be reaching the box over the LAN and proving nothing.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `502 Bad Gateway` | Tunnel is up, gateway is not. `docker compose ps` → check gateway health. |
| `530` / `1033` | Tunnel isn't connected. Check the token and `docker compose logs cloudflared`. |
| No Access prompt | The Access application isn't matching. Domain must be exact, no wildcard confusion. |
| Works on Wi-Fi, fails on cellular | You were hitting the LAN. This is the failure the test is designed to catch. |
| DNS doesn't resolve | Cloudflare should create the CNAME automatically — verify it exists in DNS. |

---

## Note on the private path

Tailscale (task 0.4) remains the **default** route. It's faster, has no third party in the data path, and works when Cloudflare doesn't. The tunnel exists for the cases Tailscale can't cover cleanly — sharing a demo, a device you haven't enrolled, a browser you don't control.

If you only ever use Tailscale, that's a good outcome. The tunnel is redundancy plus a portfolio artifact, not the primary path.
