<p align="center"><img src="assets/logo.png" width="128" alt="LighterNights logo"></p>

# LighterNights

A World of Warcraft addon that changes gamma, brightness and contrast by the
in-game time of day, so nights are easier to see and days look the way you set
them.

## What it does

The game's sky follows the server clock, and at night the world gets dark.
LighterNights watches the server time and switches your display settings when
morning, day, evening or night begins. Each of the four has its own gamma,
brightness and contrast, and the change fades in over about five seconds
instead of jumping.

Your own display values are remembered. The addon returns to them when you
switch it off and every time you log out.

## Features

- **Four sections** — Morning, Day, Evening, Night — each with its own start
  time, gamma, brightness and contrast, and a checkbox to skip it.
- **Three kinds of mode**
  - *Auto*: the section follows the server time.
  - *Morning / Day / Evening / Night*: one section stays on regardless of time.
  - *Disabled*: your own values are restored and the addon leaves them alone.
- **Smooth change** between sections, about five seconds.
- **Minimap button** whose icon shows the current time of day. Click it for the
  mode menu and a shortcut to the settings.
- **Settings window** in the game's options, under AddOns.
- **11 languages**: English, German, Spanish (Spain and Latin America), French,
  Italian, Korean, Portuguese, Russian, Simplified and Traditional Chinese.

## Installation

The addon folder must be named `LighterNights`. This repository is called
`lighter_nights`, so a plain download or clone needs renaming.

**From a release archive**

1. Download `LighterNights-<version>.zip` from the
   [Releases](https://github.com/shamahan/lighter_nights/releases) page.
2. Unpack it into your client's `Interface\AddOns` folder. You should end up
   with `Interface\AddOns\LighterNights\LighterNights.toc`.
3. Restart the game or type `/reload`.

**With git**

```
cd "World of Warcraft\_forever_\Interface\AddOns"
git clone https://github.com/shamahan/lighter_nights.git LighterNights
```

## Usage

| Command | What it does |
|---|---|
| `/ln` | Opens the settings |
| `/ln auto` | Follow the server time |
| `/ln morning`, `/ln day`, `/ln evening`, `/ln night` | Keep one section on |
| `/ln off` | Disable and restore your own values |

`/lighternights` works the same as `/ln`.

On first run the addon takes your current gamma, brightness and contrast as
your own ("baseline") values and fills the sections with defaults:

| Section | Starts at (server time) | Gamma |
|---|---|---|
| Morning | 05:30 | baseline + 0.1 |
| Day | 08:00 | baseline |
| Evening | 18:00 | baseline + 0.1 |
| Night | 21:00 | baseline + 0.3 |

Brightness and contrast start at your baseline. Change anything in the settings
window.

## Good to know

- **Times are server times.** The settings window shows the current server time
  at the top.
- **A section lasts until the next enabled one starts.** If you untick a
  section, the previous one simply continues through its hours.
- **Sliders change the picture right away only for the section that is on.** To
  tune another one, pick it as the mode first.
- **The settings are shared by all characters.** Gamma, brightness and contrast
  are client-wide game settings.
- **Changing display settings yourself.** Switch to *Disabled*, change them in
  the game's graphics options, then switch back: the addon picks up the new
  values as your baseline.
- **Do not run it together with another addon that sets gamma** (NightLight,
  for example). They will overwrite each other.
- **If the picture ever looks wrong**, type `/ln off`. As a last resort:
  `/console Gamma 1.0`, `/console Brightness 50`, `/console Contrast 50`.

## Compatibility

Developed and tested on the Forever client (`_forever_`, Interface 16001).

Retail (Interface 120105, 120107) is declared in the `.toc`, but the addon has
not been tested on retail yet.

## Development

The logic for the schedule, the fade and the modes is covered by unit tests
that run outside the game under Lua 5.1 (through the Python package `lupa`).
The settings window and the minimap button are exercised against a mock of the
game's widgets.

```
python -m venv .venv
.venv\Scripts\python -m pip install lupa pillow
.venv\Scripts\python tests\run.py
```

`tools/make_icons.py` and `tools/make_logo.py` draw the icons and the logo;
`tools/package.py` builds the release archive.

## How it was made

LighterNights was designed, written and reviewed with
[Claude](https://www.anthropic.com/claude), Anthropic's AI model, working in
Claude Code. The author set the requirements, made the decisions and tested the
addon in the game.

## Credits

Embedded libraries, each by its own authors: LibStub, CallbackHandler-1.0,
LibDataBroker-1.1, LibDBIcon-1.0.

## License

Copyright © 2026 Vovkulaka. All rights reserved. See [LICENSE](LICENSE).
