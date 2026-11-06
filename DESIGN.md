# Squeek Odometer: design system

Taken from the source: `dist/style.css` (tokens and all component CSS), `dist/index.html`, `dist/led.js` (the LED
board) and `dist/app.js`. There is no build step; `dist/` is the site.

## Overview

A one-page mint site that sits in Squeekchain's own visual world: a cool grey page, light rounded panels, a monospace
voice with small uppercase tracked labels, condensed bold uppercase headings, a black primary button and a black LED
dot-matrix board for the live wheel. The art itself (the odometers, drawn by the contract) is the only pixel art on the
page and always sits on a dark frame, so it reads as a screen. Squeekchain's logo is not used; the page's mark is the
odometer itself.

Order of the page: header bar, hero (headline, mint, your odometer), live row (LED board, numbers), How it works,
Traits, Latest, Contract, FAQ, footer.

## Colors

All colors are custom properties in `:root` of `dist/style.css`.

| Token | Value | Use |
| --- | --- | --- |
| `--page` | `#c9cad2` | page background (the Squeekchain grey) |
| `--panel` | `#f4f4f6` | header bar, panels, line buttons |
| `--sunk` | `#e8e8ed` | cards and tables inside panels, inline `code` |
| `--line` | `#d5d6de` | 1px panel and button borders, dashed row rules |
| `--ink` | `#16161b` | headings, values, strong text |
| `--text` | `#2a2a33` | body text |
| `--muted` | `#5a5b67` | labels, fine print, table second column |
| `--solid` / `--solid-hover` | `#16161b` / `#2e2e37` | primary button |
| `--accent` | `#c2700c` | the hamster orange: the second line of the headline, step numbers, bullets, connected dot |
| `--link` | `#3346b8` | links, focus outline, "napping" |
| `--good` / `--bad` | `#2f6b2a` / `#a3271c` | success and error messages, "running" |
| `--led-bg` | `#0e0e11` | LED board, the frame around every odometer image |

LED board dot colors live in `dist/led.js` (`C`): unlit `#1f1f25`, orange `#f6a63b`, cream `#f3e9cc`, grey `#7d7d88`,
blue `#8fa2ff`, green `#7fe08a`, rim `#9a9aa6`. The odometer art keeps the contract's own palette.

## Typography

- `--font-mono`: IBM Plex Mono 400 and 500 (WOFF2 in `dist/fonts/`, SIL OFL 1.1, licenses alongside), falling back to
  the system monospace stack. Body text, labels, buttons, nav, numbers.
- `--font-head`: Barlow Condensed 700 (WOFF2 in `dist/fonts/`, SIL OFL 1.1), uppercase, line-height 0.98. Headings,
  the brand, FAQ questions.
- Scale: `--fs-1` 12px (labels, small buttons), `--fs-2` 14px (fine print, nav, buttons, tables), `--fs-3` 16px (body),
  `--fs-4` 22px (h3, brand), `--fs-5` 36px (h2), `--fs-6` 60px (h1; 48px under 900px, 40px under 640px).
- Labels (`.label`, `dt`, nav, buttons) are uppercase with `--track` 0.12em letter-spacing. Body text is never
  uppercase. Numbers that line up use `.num` (tabular figures).

## Layout

- Spacing on a 4px base: `--s-1` 4, `--s-2` 8, `--s-3` 12, `--s-4` 16, `--s-5` 24, `--s-6` 40.
- `main` is one column of panels at most 1440px wide with `--s-3` gaps (`--s-2` on phones). The header bar is sticky,
  floats `--s-3` from the top and has the same width.
- Hero: two columns (text 1.25fr, your odometer 1fr). Live row: LED board 2.2fr, numbers 1fr. Contract: two equal
  columns. All stack under 900px.
- Inner grids auto-fit: steps `minmax(min(100%, 220px), 1fr)`, trait tables 230px, latest cards 168px. The stage strip
  is one row that scrolls sideways (148px items on phones).
- Phones (640px and narrower): the nav moves to its own scrolling row, the wallet button says "Connect", the mint button
  takes the full width, panels pad `--s-5 --s-4`. Checked at 390px with no horizontal page scroll.

## Elevation & depth

Flat. Panels are separated by the grey page and a 1px `--line` border. The header bar is translucent `--panel` with a
6px backdrop blur so content scrolling under it stays readable; that is the only blur. Odometer images sit in a
`--led-bg` frame. One soft orange radial tint sits behind the hero art. Stacking: header bar `z-index: 10`, skip link 20.

## Shapes

Panels and the LED board: 12px radius (`--r-panel`). Buttons: 6px (`--r-ctl`). Cards, tables and steps inside panels:
8px. Odometer images: 6px inside their frame, `image-rendering: pixelated`. Bullets in Contract are 8px orange dots.

## Components

- **Button** `.btn` + `.solid` (black, the one main action per view: Mint), `.line` (bordered, header wallet, Watch the
  stream, Ask marketplaces to redraw) or `.text` (a quiet link-button), sized by default 44px, `.solid` 48px,
  `.small` 36px. Disabled is 45% opacity; a running write sets `aria-busy`. The wallet button carries a small square
  that turns orange once connected and then shows the short address in normal case.
- **LED board** (`dist/led.js`, `window.LedBoard.set({ state, km, rpm, block })`): a canvas of round dots that sizes
  itself to its lines (6.5px pitch on wide screens, 5px on phones). Lines: SQUEEKTOSHI, his state, HAS RUN, the
  distance (double size when it fits), RPM, Squeek block. A dot wheel on the right turns while he runs, faster with the
  RPM; while he naps only a Z blinks; with reduced motion it is still. Its `aria-label` carries the same facts, and the
  numbers panel beside it repeats them as text.
- **Key-value list** `.kv`: uppercase `dt` left, value right, dashed rules. Used for the live numbers and addresses.
- **Steps** `.steps`: numbered sunk cards (orange `01` to `04`).
- **Stage strip** `.strip`: the seven sample odometers from `dist/samples/` (rendered by the contract through
  `script/Gallery.s.sol`), caption stage left and distance right.
- **Trait tables** `.t`: sunk card, condensed heading with a small right-aligned note, two-column table.
- **Cards** `.card`: a minted odometer with `#id`, km and status.
- **FAQ**: native `details`/`summary`, condensed uppercase question, `+` / `-` marker.
- **Messages** `#msg`: one `role="status"` line under the mint button for every wallet step, success or error.

## Do's and Don'ts

- Do keep one black button per view; everything else is `.line` or `.text`.
- Do put new numbers in a `.kv` list and new explanations in `.fine` text next to what they explain.
- Do use the tokens above, not new hex values. Orange is an accent, never a background behind text.
- Do show the contract's art on a dark frame and at a pixel-exact multiple where possible.
- Don't copy Squeekchain's logo or its dot-matrix wordmark; the LED board is the shared language, the words are ours.
- Don't use uppercase for sentences, or more than one accent color in a heading.

Recipe: add a `section.panel` with a `.label` kicker and an `h2`, fill it with `.kv`, `.steps`, `.t` or `.grid`, and
read the chain through `call()` / `rpc()` in `dist/app.js`.
