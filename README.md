# Piped-Docker

This is a fork of [TeamPiped/Piped-Docker](https://github.com/TeamPiped/Piped-Docker). It sets up Piped the same way, but its compose templates use fixed builds of the frontend, the backend, the proxy and the bg-helper instead of the official images, and add a small service for SABR playback. Everything else (Postgres, nginx, Caddy and Watchtower) still uses the official images. It also offers automatic updates with Watchtower for every stack type, including standalone, which the official repository sets up without them.

For general self-hosting instructions, see https://piped-docs.kavin.rocks/docs/self-hosting/#docker-compose-caddy-aio-script

## Why this fork

| Service | Official image | This fork | What it fixes |
|---|---|---|---|
| Frontend | `1337kavin/piped-frontend` | `ghcr.io/noahbroyles/piped-frontend` ([source](https://github.com/noahbroyles/Piped)) | Live streams load the watch page but then spin on the thumbnail forever while the time keeps advancing. YouTube names the audio segments of its live HLS streams `seg.ts` although they are packed AAC, so Shaka Player treats them as MPEG-TS and never lines the audio up with the video. The fixed frontend renames those segments so Shaka handles them as AAC. It also updates Shaka Player to 5.2.12.<br><br>It also plays videos over [SABR](#sabr) when the backend offers it, in every quality YouTube has (up to 4K). |
| Backend | `1337kavin/piped` | `ghcr.io/noahbroyles/piped-backend` ([source](https://github.com/noahbroyles/Piped-Backend)) | Videos are only available in 360p. The official image ships an outdated NewPipeExtractor, which can make `/streams` return only YouTube's single 360p stream with audio and video combined (itag 18), with no higher resolutions or separate audio streams. The fork updates NewPipeExtractor to upstream commit `01fdde0` (Piped-Backend PR #895).<br><br>**Security:** it also fixes six security problems in the official backend, listed [below](#backend-security-fixes).<br><br>It also adds what a SABR player needs to `/streams` (see [SABR](#sabr)). |
| Proxy | `1337kavin/piped-proxy` | `ghcr.io/noahbroyles/piped-proxy` ([source](https://github.com/noahbroyles/piped-proxy)) | The official proxy only allows `GET` requests, so it can't carry SABR, which `POST`s every request. The fork passes SABR requests through and keeps SABR redirects on the proxy, so your browser never contacts Google directly. |
| bg-helper | `1337kavin/bg-helper-server` | `ghcr.io/noahbroyles/bg-helper-server` ([source](https://github.com/noahbroyles/bg-helper-server)) | YouTube no longer accepts the PoTokens that the official image mints: googlevideo treats them as if there were no token at all, so SABR streams stop after their first minute. The official image solves a BotGuard challenge from an API endpoint, while YouTube's own player uses the challenge that the youtube.com homepage carries, together with that page's configuration. The fork does the same, and keeps the token minter between requests instead of solving a challenge for every video. |
| Player n decoder | none | `ghcr.io/noahbroyles/piped-player-n-decoder` ([source](https://github.com/noahbroyles/piped-player-n-decoder)) | New. YouTube only serves SABR streams when the `n` parameter of their URL is deciphered with its own player code, which NewPipeExtractor can no longer do. This small service does it for the backend. |

The frontend, backend, proxy and bg-helper images are drop-in replacements for the official ones: they read the same configuration and environment variables. All the images are public (no login needed), built for `linux/amd64` and `linux/arm64`, and published on every push to the default branch of their repositories (`master` for the frontend and backend, `main` for the proxy, the bg-helper and the n decoder). When automatic updates are on, Watchtower keeps them updated from GitHub Container Registry like the official images, because it selects containers by name rather than by image.

### Backend security fixes

The official backend image has these security problems, which the fork's backend fixes. Any instance that is reachable from the internet is exposed to them, whether or not it allows registration.

-   **Server-side request forgery (SSRF).** Anyone who can reach the API, without logging in, can make the backend send requests to other addresses, such as devices on your local network.
-   **Libraries with 23 known vulnerabilities** (Jackson, Bouncy Castle, the PostgreSQL driver, jsoup and the MinIO client). The fork upgrades them to fixed releases.
-   **No limit on request size.** A single huge request, such as a 100 MB login, is read fully into memory before being rejected, and larger ones leave the connection hanging. The fork rejects requests over 5 MiB (16 KiB for login and registration).
-   **Stack traces in error responses.** Errors send the full Java stack trace to whoever made the request, which shows the server's internal code paths, library versions and other details. The fork returns only a short reason, such as `This video is private.`, and keeps the stack trace in the backend's log.
-   **No limit on channel lists from users without an account.** Every unknown channel ID sent to the feed and subscription endpoints is stored in the database and looked up on YouTube, so one request with thousands of made-up IDs can fill your database and make your server flood YouTube with requests, which risks YouTube rate-limiting or blocking your server's IP address. The fork rejects requests with more than 1000 channels and looks up at most 25 unknown channels per request.
-   **Fake new-video notifications.** Anyone can send fake notifications to the backend's PubSub webhook, which makes it fetch arbitrary videos from YouTube through a queue with no size limit, and its subscription check writes whatever channel ID it is given to your database. The fork's webhook only confirms subscriptions the backend asked for, caps its queue, and verifies notifications with a secret (see below).

#### PubSub verification

The last fix needs a secret, `PUBSUB_SECRET` in `config/config.properties`. On a new installation, `configure-instance.sh` generates a random one for you, so there is nothing to do.

On an existing installation, add it yourself. Generate a secret:

```sh
openssl rand -hex 32
```

Add it to `config/config.properties`, then restart the backend with `docker compose restart piped`:

```
PUBSUB_SECRET:<the generated value>
```

Without it, the backend logs a warning at startup and accepts notifications from anyone. Keep the secret private and do not change it later. Notifications for subscriptions made before it was set (or with an older secret) are dropped until those subscriptions renew, within about 4 days, so some new videos may be missing from feeds during that time.

## SABR

YouTube's web player streams videos with SABR (server adaptive bitrate). Instead of fetching each quality from its own URL, the player `POST`s its playback state to a single streaming URL, and YouTube decides which pieces of video to send back. YouTube is moving more and more videos to SABR only, which is what limits other clients to 360p.

With this fork, the backend adds a `sabr` object to `/streams`, and the frontend plays it with [googlevideo](https://github.com/LuanRT/googlevideo)'s SABR adapter, the way YouTube's own player does. All of it still goes through your proxy. It needs:

-   the n decoder (`PLAYER_N_DECODER_URL` in `config.properties`), without which the backend leaves `sabr` out;
-   the bg-helper (`BG_HELPER_URL`), for the PoToken that YouTube expects with every SABR request;
-   `PROXY_PUBLIC_URL` on the proxy, its public URL, since SABR redirects have to point back at it. `configure-instance.sh` sets it for you.

When SABR doesn't work for a video, the frontend falls back to the regular streams. To turn SABR off, set `DISABLE_SABR:true` in `config.properties` for the whole instance, or turn off "Use SABR streaming" in the frontend's preferences for one browser.

## New installation

Use this repository in place of the official one, and follow the rest of the official guide as usual:

```sh
git clone https://github.com/noahbroyles/Piped-Docker
cd Piped-Docker
./configure-instance.sh
docker compose up -d
```

## Automatic updates

`configure-instance.sh` asks whether to enable automatic updates with [Watchtower](https://github.com/nicholas-fedor/watchtower). They are recommended and on by default: press Enter to keep them, or answer `n` to turn them off. This works the same for the caddy, nginx and standalone stacks.

With automatic updates on, Watchtower checks once a day for new builds of every container in the stack, then pulls them and recreates the containers with the same settings, removing the old images. Because the images use the `latest` tag, every change pushed to the `master` branch of the frontend or backend repository reaches your instance within a day. If you would rather choose when to update, turn automatic updates off, or pin `sha-<commit>` tags as described below.

With automatic updates off, update by hand with `docker compose pull` followed by `docker compose up -d`.

To add Watchtower to an existing installation without rerunning the script, copy the block between `# BEGIN watchtower` and `# END watchtower` from the template for your stack in [`template/`](template) into the `services` section of your `docker-compose.yml`, then run `docker compose up -d`. If you renamed any containers, update the container names listed on its `command` line to match. To remove it again, delete that block and run `docker compose up -d --remove-orphans`.

## Switching an existing installation

Do not rerun `configure-instance.sh` on an existing installation. It deletes and regenerates the `config/` directory, which would throw away any changes you made to `config/config.properties`.

Instead, edit the `docker-compose.yml` of your installation and change only the `image` lines of the frontend, backend and proxy services. Keep everything else, including the volume that mounts your `config.properties` into the backend.

```diff
-        image: 1337kavin/piped-frontend:latest
+        image: ghcr.io/noahbroyles/piped-frontend:latest
```

```diff
-        image: 1337kavin/piped:latest
+        image: ghcr.io/noahbroyles/piped-backend:latest
```

```diff
-        image: 1337kavin/piped-proxy:latest
+        image: ghcr.io/noahbroyles/piped-proxy:latest
```

For [SABR](#sabr), also:

1.  Add your proxy's public URL to the `environment` of the proxy service (use your own hostname):

    ```yaml
            - PROXY_PUBLIC_URL=https://pipedproxy.example.com
    ```

2.  Copy the `piped-player-n-decoder` service from the template for your stack in [`template/`](template) into the `services` section, and add `piped-player-n-decoder` to the container names on Watchtower's `command` line if you use it.

3.  Add this line to `config/config.properties`:

    ```
    PLAYER_N_DECODER_URL:http://piped-player-n-decoder:3001
    ```

Then pull the new images and recreate the containers:

```sh
docker compose pull
docker compose up -d
```

To go back to the official images, change the `image` lines back, remove the n decoder service and run the same two commands.

## Pinning a version

All the images are published with two kinds of tags:

-   `latest` follows the default branch of the image's repository.
-   `sha-<commit>` pins a specific build, using the short commit hash from that repository.

## Problems

If one of these images misbehaves, please open an issue on [noahbroyles/Piped](https://github.com/noahbroyles/Piped/issues) (frontend), [noahbroyles/Piped-Backend](https://github.com/noahbroyles/Piped-Backend/issues) (backend), [noahbroyles/piped-proxy](https://github.com/noahbroyles/piped-proxy/issues) (proxy) or [noahbroyles/piped-player-n-decoder](https://github.com/noahbroyles/piped-player-n-decoder/issues) (n decoder). For problems with the compose setup itself, open an issue on [this repository](https://github.com/noahbroyles/Piped-Docker/issues).
