# Piped-Docker

This is a fork of [TeamPiped/Piped-Docker](https://github.com/TeamPiped/Piped-Docker). It sets up Piped the same way, but its compose templates use fixed builds of the frontend and the backend instead of the official images. Everything else (the proxy, the bg-helper, Postgres, nginx, Caddy and Watchtower) still uses the official images. It also offers automatic updates with Watchtower for every stack type, including standalone, which the official repository sets up without them.

For general self-hosting instructions, see https://piped-docs.kavin.rocks/docs/self-hosting/#docker-compose-caddy-aio-script

## Why this fork

| Service | Official image | This fork | What it fixes |
|---|---|---|---|
| Frontend | `1337kavin/piped-frontend` | `ghcr.io/noahbroyles/piped-frontend` ([source](https://github.com/noahbroyles/Piped)) | Live streams load the watch page but then spin on the thumbnail forever while the time keeps advancing. YouTube names the audio segments of its live HLS streams `seg.ts` although they are packed AAC, so Shaka Player treats them as MPEG-TS and never lines the audio up with the video. The fixed frontend renames those segments so Shaka handles them as AAC. It also updates Shaka Player to 5.2.12. |
| Backend | `1337kavin/piped` | `ghcr.io/noahbroyles/piped-backend` ([source](https://github.com/noahbroyles/Piped-Backend)) | Videos are only available in 360p. The official image ships an outdated NewPipeExtractor, which can make `/streams` return only YouTube's single 360p stream with audio and video combined (itag 18), with no higher resolutions or separate audio streams. The fork updates NewPipeExtractor to upstream commit `01fdde0` (Piped-Backend PR #895).<br><br>**Security:** it also fixes six security problems in the official backend, listed [below](#backend-security-fixes). |

Both images are drop-in replacements for the official ones: they read the same configuration and environment variables. They are public (no login needed), built for `linux/amd64` and `linux/arm64`, and published on every push to the `master` branch of their repositories. When automatic updates are on, Watchtower keeps them updated from GitHub Container Registry like the official images, because it selects containers by name rather than by image.

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

Instead, edit the `docker-compose.yml` of your installation and change only the `image` lines of the frontend and backend services. Keep everything else, including the volume that mounts your `config.properties` into the backend.

```diff
-        image: 1337kavin/piped-frontend:latest
+        image: ghcr.io/noahbroyles/piped-frontend:latest
```

```diff
-        image: 1337kavin/piped:latest
+        image: ghcr.io/noahbroyles/piped-backend:latest
```

Then pull the new images and recreate the containers:

```sh
docker compose pull
docker compose up -d
```

To go back to the official images, change the two `image` lines back and run the same two commands.

## Pinning a version

Both images are published with two kinds of tags:

-   `latest` follows the `master` branch of the image's repository.
-   `sha-<commit>` pins a specific build, using the short commit hash from that repository.

## Problems

If the frontend or the backend misbehaves with these images, please open an issue on [noahbroyles/Piped](https://github.com/noahbroyles/Piped/issues) (frontend) or [noahbroyles/Piped-Backend](https://github.com/noahbroyles/Piped-Backend/issues) (backend). For problems with the compose setup itself, open an issue on [this repository](https://github.com/noahbroyles/Piped-Docker/issues).
