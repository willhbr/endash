# endash

_Container dashboard for Podman_

![screenshot of endash with containers](https://github.com/willhbr/endash/raw/main/endash.webp)

## Installation

You'll have to build this one yourself. I build it using [pod][pod] but you can just use `podman build` if you want.

[pod]: https://pod.willhbr.net

```console
$ git clone https://github.com/willhbr/endash.git
$ cd endash
$ podman build --tag=endash:prod-latest --file=Containerfile.prod .
```

You could also run it outside of a container, but that's not what the artist intended.

## Usage

endash does not store any state, and is configured by command-line flags. The `--host` flag is a JSON object that is repeated for each podman-remote host to show connections from. For example:

```
$ ./endash '--host={"name": "localhost", "hostname": "localhost", "podman_url": "unix:///run/user/podman/podman.sock"}'
```

If you use [pod][pod] you can write the flags as YAML and they'll get auto-translated to JSON (that's the whole point of this feature).

To connect to podman on the same machine:

```yaml
host:
  name: localhost
  hostname: localhost
  podman_url: "unix:///run/user/podman/podman.sock"
  container_refresh: 5m
```

You may need to change `podman_url` if you're running rootless.

To connect to a remote machine:

```yaml
host:
  name: homelab
  hostname: homelab
  podman_url: "ssh://will@homelab:22/run/user/1000/podman/podman.sock"
  identity: /var/run/secrets/homelab-ssh-key
  container_refresh: 10m
```

To run endash in a container, you'll need to bind mount the podman socket. If you want to access a remote machine, either bind mount your `.ssh` directory or use podman secrets to manage the private key.

Here's a config that I use:

```yaml
containers:
  prod:
    name: endash-prod
    image: endash:prod-latest
    ports:
      5049: 80
    bind_mounts:
      /run/user/1000/podman/podman.sock: /run/user/podman/podman.sock
    # I use `pod secrets` to create this secret from a file on my dev machine
    secrets:
      steve-ssh-key:
        local: /home/will/.ssh/steve_id_ed25519
    flags:
      # podman runs an empty container for some reason and I want to hide it
      ignore_systemd_sleep: true
      host:
        name: badger
        hostname: badger
        podman_url: "ssh://prod@badger:22/run/user/1000/podman/podman.sock"
        identity: /var/run/secrets/steve-ssh-key
        container_refresh: 15m
        # The cache usually only applies to non-interactive endpoints,
        # but since this host is really slow, just show the cached info.
        ui_shows_cached: true
        timeout: 20s
      host:
        name: steve
        hostname: steve
        podman_url: "unix:///run/user/podman/podman.sock"
        container_refresh: 5m
      host:
        name: brett
        hostname: brett
        podman_url: "ssh://will@brett:22/run/user/1000/podman/podman.sock"
        identity: /var/run/secrets/steve-ssh-key
        container_refresh: 10m
    # Endash uses labels to expose links and prometheus info
    labels:
      # Will advertise /metrics on whatever the host port for :80 is
      prometheus.port: 80
      # These are added to the service definition verbatim
      prometheus.labels:
        __scrape_interval__: 10m
      # Links are auto-mapped to the corresponding public port
      # Any exposed ports are automatically added as links if they're not given a label
      endash.links:
        - name: Status
          port: 80
          path: /status
        - name: Dash
          port: 80
```

I use this config in Prometheus to enable service discovery:

```yaml
scrape_configs:
  - job_name: endash
    http_sd_configs:
      - url: http://host.containers.internal:5049/prometheus
```

`host.containers.internal` allows the prometheus container (running on the same host as endash) to access ports on the host. Any new container on any host with the `prometheus.port` label will be picked up automatically.

## Contributing

1. Fork it (<https://github.com/willhbr/endash/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Will Richardson](https://willhbr.net) - creator and maintainer
