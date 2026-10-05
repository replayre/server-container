# Container packaging for the replay.re Cyberpunk 2077 Multiplayer Server (`REServer`, Linux)

* [Running](#running)
* [Ports](#ports)
* [Updating](#updating)
* [Console access](#console-access)
* [Volume and mounts](#volume-and-mounts)

This README is written for a more technical audience. If you are looking for user friendly documentation, please visit
the [replay.re Docs](https://docs.replay.re/servers/quick-start/)

The install directory of the server is a **volume**, which gets seeded during first launch with
binaries bundled during image build time. The image contains this seed data in `/opt/replay/seed`,
which the entrypoint copies into `/srv` **when the volume holds no server yet**.

From then on the installation gets updated via the servers built-in updater logic.

## Running

We recommend using the provided `compose.yaml`, which provides host-visible `cfg/`, `logs/` and `ugc/`.

You can access the console output via `podman logs`/`docker logs` or browse `logs/` for the actual
server logs.

Alternatively you can also launch the image directly via:
```sh
podman run -d --name replay-server --restart=unless-stopped \
  -p 20770:20770/udp -p 20770:20770/tcp -p 20771:20771/udp -p 20771:20771/tcp \
  -v replay-server:/srv \
  ghcr.io/replayre/server
```

The first start copies the bundled data into the volume and creates `cfg/server.cfg` from the shipped
example.

## Ports

Defaults: `20770` for the game (TCP + UDP) and `20771` for VoIP (TCP + UDP).

Both are forced onto the server from the environment (`GAME_PORT`, `VOIP_PORT`), which outranks
anything `cfg/server.cfg` says about them.

Change them here, not in the cfg:
```sh
podman run -d -e GAME_PORT=30770 -p 30770:30770/udp -p 30770:30770/tcp -v replay-server:/srv ghcr.io/replayre/server
```

`compose.yaml` passes both sides from the same variable, so a single `GAME_PORT=30770` in your
environment file moves the server and its published ports together.

The address players are told to connect to is separate from what the server listens on.
Set `sv_endpoint` in `cfg/server.cfg` to the public `host:port` when the server is behind NAT,
a load balancer or a DNS name.

## Updating

The server contains a built-in updater. On every start it fetches the manifest of its channel and
compares it against what is installed. With automatic updates, the default, the differences are
downloaded and applied before the server starts. The `CHANNEL` is written into 
`settings/server.settings.json` on every start. `alpha` is currently the only channel:
```sh
podman run -d --name replay-server -e CHANNEL=alpha -v replay-server:/srv ghcr.io/replayre/server
```

### Automatic

`AUTO_UPDATE=true` (the default) applies a pending update before the server starts.

Depending on what has been updated, two scenarios can happen:
- **Content only** (config, modules, data): The server simply boots with the new files
- **The server executable**: The process applies the update, exits, expects to be started again.
  In a container it cannot restart itself, so give it a restart policy (`restart: unless-stopped`).

`RESTART_AFTER_UPDATE` has **no effect inside a container** and does not need to be set.
It exists for non-containerised servers, where `auto` relaunches the process directly when a console
is attached and `always` or `never` force or suppress that relaunch.

### Manual

With `AUTO_UPDATE=false` nothing is written at startup. The server reports that an update is
available, boots the installed revision, and waits for you to apply it.

**From the console**: attach as described in [Console access](#console-access) and type `update`.
The server checks for updates, shuts down gracefully, applies the update and exits. 
The restart policy brings it back up after the update.

If there is nothing to apply, or the download server cannot be reached, it reports that and keeps running.

**With a one-shot run**:
```sh
podman run --rm -e CHANNEL=alpha -v replay-server:/srv ghcr.io/replayre/server --update
```

`--update` applies whatever is pending regardless of `AUTO_UPDATE`, so the flag alone is enough, but
pass the same environment your deployment uses, `CHANNEL` included.

If there is **nothing to apply**, the run falls through to starting the server instead of exiting,
so it does not terminate on its own. Wrap it in a `timeout` when scripting it, or treat a
still-running process as "already current".

### What the updating process modifies

Files that are not part of the published manifest are never downloaded and never deleted, so `cfg/`,
`settings/`, `logs/` and `data/ugc/` survive any update. The only things the updater removes are
leftovers like `*.old`, backups and staged `*.reupdate` downloads.

## Console access

The server currently has **no RCON interface**, you control it by attaching to the container:

```sh
podman run -dit --name replay-server -v replay-server:/srv ghcr.io/replayre/server
podman attach replay-server             # `>> ` prompt 
                                        # `exit` stops the server
                                        # detach with Ctrl-P Ctrl-Q
```

The container has to have been started **with a tty** (`-t` or `tty: true` in `compose.yaml`).

The server checks its standard input once at startup. Without a tty the console is
silenced and nothing typed into an attached terminal reaches it. 

Without a tty the server is configured entirely through `cfg/`, and updates are applied by the
updater at startup (see [Updating](#updating)).

`stop` reaches the server as `SIGTERM`, which it handles as a graceful shutdown.

## Volume and mounts

All paths are relative to the working directory, which the entrypoint sets to `/srv`:

| path | contents |
| --- | --- |
| `/srv` | The server root directories with its binaries |
| `/srv/cfg/` | `server.cfg` and any other configs |
| `/srv/settings/` | `server.settings.json` (`auto_update`, `restart_after_update`, `channel`), rewritten from the environment on every start |
| `/srv/logs/` | `server_<timestamp>.txt`, files older than 7 days are pruned |
| `/srv/data/ugc/` | UGC bundles |

`cfg/`, `logs/` and `data/ugc/` are safe to mount from the host, which is what `compose.yaml` does.
The rest of `/srv` belongs to the server and the updater.

