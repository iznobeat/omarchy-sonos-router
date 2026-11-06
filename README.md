# Sonos Router for Omarchy

Send **one app's** audio to any Sonos (or other AirPlay) speaker from the
Omarchy bar, while everything else keeps playing on your laptop.

Click the speaker icon in the bar, and every app that is playing sound shows
up with a button per output: **This computer**, plus each AirPlay speaker on
your network. Click a speaker to send that app there; click **This computer**
to bring it back.

- Per-app routing, not all-or-nothing
- Works with any AirPlay receiver that PipeWire can discover (Sonos speakers,
  stereo pairs and groups, other AirPlay 2 speakers)
- No cloud, no account, no background service: just PipeWire's built-in
  AirPlay (RAOP) sinks and `pactl`
- Keyboard: arrows / `hjkl` to move, `Enter` to send, `r` to send everything back
- Middle-click the bar icon to send everything back to this computer
- English and Norwegian

## Requirements

- Omarchy with the plugin-capable `omarchy-shell`
- PipeWire with Zeroconf support: `sudo pacman -S --needed pipewire-zeroconf`
- `pactl` and `jq` (both standard on Omarchy)

## Install

```sh
omarchy plugin add https://github.com/iznobeat/omarchy-sonos-router.git --enable
```

or, from a local checkout:

```sh
git clone https://github.com/iznobeat/omarchy-sonos-router.git
ln -sfn "$PWD/omarchy-sonos-router" ~/.config/omarchy/plugins/jhgundersen.sonos-router
omarchy plugin enable jhgundersen.sonos-router --section right
```

### Turn on AirPlay discovery in PipeWire

The plugin does not change system config by itself. Copy the included file
and restart audio:

```sh
install -Dm644 extras/50-raop-discover.conf ~/.config/pipewire/pipewire.conf.d/50-raop-discover.conf
systemctl --user restart pipewire pipewire-pulse wireplumber
```

Your speakers should now be listed by `wpctl status`.

### Firewall

AirPlay speakers send timing packets back to the computer over UDP. With
`ufw` on, the speaker connects but stays silent. Allow your local network:

```sh
sudo ufw allow from 10.0.0.0/24 comment 'LAN / AirPlay'   # use your own subnet
```

## Tips

- **Latency.** AirPlay buffers about 2–3 seconds. That's fine for music, but
  video will be out of sync.
- **Crackling or dropouts.** Raise `sess.latency.msec` in
  `50-raop-discover.conf` (it is already about 1 s), or use 5 GHz or wired
  networking.
- **Routes reset when the app closes.** WirePlumber normally remembers which
  output an app was moved to. To have every app start on the default output
  again, put this in `~/.config/wireplumber/wireplumber.conf.d/no-restore-target.conf`:
  ```
  wireplumber.settings = { node.stream.restore-target = false }
  ```
- **Multiple rooms at once.** Group the speakers in the Sonos app, then pick
  the group's leading speaker here.

## CLI

The panel is a thin UI over `bin/sonos-router`, which you can also use directly:

```
sonos-router list                  # JSON: default output, outputs, app streams
sonos-router move <stream> <sink>  # move one app stream to a sink by name
sonos-router reset <stream>        # move one app stream back to the default output
sonos-router reset-all             # move every app on AirPlay back
```

## License

MIT
