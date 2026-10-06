# Piped-Docker

This is a fork of [TeamPiped/Piped-Docker](https://github.com/TeamPiped/Piped-Docker). It sets up Piped the same way, but its compose templates use fixed builds of the frontend and the backend instead of the official images. Everything else (the proxy, the bg-helper, Postgres, nginx, Caddy and Watchtower) still uses the official images.

For general self-hosting instructions, see https://piped-docs.kavin.rocks/docs/self-hosting/#docker-compose-caddy-aio-script

## Why this fork

| Service | Official image | This fork | What it fixes |
|---|---|---|---|
| Frontend | `1337kavin/piped-frontend` | `ghcr.io/noahbroyles/piped-frontend` ([source](https://github.com/noahbroyles/Piped)) | Live streams load the watch page but then spin on the thumbnail forever while the time keeps advancing. YouTube names the audio segments of its live HLS streams `seg.ts` although they are packed AAC, so Shaka Player treats them as MPEG-TS and never lines the audio up with the video. The fixed frontend renames those segments so Shaka handles them as AAC. It also updates Shaka Player to 5.2.12. |
| Backend | `1337kavin/piped` | `ghcr.io/noahbroyles/piped-backend` ([source](https://github.com/noahbroyles/Piped-Backend)) | The official image ships an outdated NewPipeExtractor, which can make `/streams` return a single progressive stream (itag 18) with no audio streams. The fork updates NewPipeExtractor to upstream commit `01fdde0` (Piped-Backend PR #895). |

Both images are drop-in replacements for the official ones: they read the same configuration and environment variables. They are public (no login needed), built for `linux/amd64` and `linux/arm64`, and published on every push to the `master` branch of their repositories. Watchtower selects containers by name, so it keeps them updated from GitHub Container Registry like the official images.

## New installation

Use this repository in place of the official one, and follow the rest of the official guide as usual:

```sh
git clone https://github.com/noahbroyles/Piped-Docker
cd Piped-Docker
./configure-instance.sh
docker compose up -d
```

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
