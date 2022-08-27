# Zitrus

A set of opinionated system information fetchers written in Zig, for use in
[lemonbar](https://github.com/LemonBoy/bar).

## Building

Requires Zig 0.10.0.

`zig build` will build all the fetchers, <code>zig build <i>name</i></code>
will build just the specified fetcher.

## Fetchers

### `cpu`

Displays CPU utilization as a percentage alongside per-core bars.

<pre><b>cpu</b> [<i>interval</i>] [<i>color</i> ...]</pre>

- `interval`: Time between updates, in milliseconds. Defaults to 1000. Shorter
  intervals will lead to faster updates but less useful measurements.
- `color`: RRGGBB formatted color. Bars will use these colors blended
  first-to-last based on percentage. Bars will be colorless if not present.

### `ram`

<pre><b>ram</b> [<i>interval</i>] [<i>color</i> ...]</pre>

Displays RAM usage as total percentage alongside a colored bar.

- `interval`: Time between updates, in milliseconds. Defaults to 1000.
- `color`: RRGGBB formatted color. Bar will use these colors blended
  first-to-last based on percentage. Bar will be colorless if not present.

### `net`

Displays download/upload speed of all interfaces (excluding loopback).

<pre><b>net</b> <b>down</b>|<b>up</b> [<i>interval</i>]</pre>

- `interval`: Time between updates, in milliseconds. Defaults to 1000. Shorter
  intervals will lead to faster updates but less useful measurements.

### `bspwm`

Displays list of current occupied bspwm desktops, with the focused desktop
highlighted. Requires `bspc` to be on `$PATH`.

<pre><b>bspwm</b> <i>monitor_name</i> [<i>focus_color</i>]</pre>

- `monitor_name`: Name of monitor whose desktops will be displayed. `bspc query
  -M --names` can be useful to figure out the name.
- `focus_color`: Color used to highlight focused desktop.
