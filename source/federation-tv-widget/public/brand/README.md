# Federation Watchtower brand kit

Federation Watchtower is a public-facing agent observability network presented as a retro-future broadcast. The visual language is **1950s anime pop art meets municipal control room**: inked character silhouettes, warm signal colors, and restrained blue monitor light.

## Core mark

The mark is the **F-signal**: a broadcast badge whose negative space forms a dominant `F`. Use `federation-f-mark.svg` at 1:1. Keep clear space equal to the badge's inner stroke width. Never stretch, bevel, or add a drop shadow.

## Palette families

`tokens.css` defines four named themes:

- `watchtower` — brick, signal yellow, soot, and monitor blue (default)
- `relay` — rust, cream, teal, and cobalt
- `foundry` — charcoal, orange, brass, and cyan
- `night-shift` — ink, coral, lemon, and electric blue

Themes are deliberately token-compatible. An organization can select one theme without changing component markup.

## Type and texture

- UI and audit feed: system sans + monospace for packet data.
- Headlines: use a condensed grotesk if available; fall back to `Arial Narrow`, `Roboto Condensed`, or system sans.
- Use flat fills, 1–2px ink outlines, and halftone dots only in large display surfaces. Avoid image filters and large assets so the widget remains fast on low-power machines.

## Files

- `federation-f-mark.svg` — primary scalable logo
- `federation-wordmark.svg` — horizontal lockup for headers
- `federation-watchtower-thumbnail.jpg` — square Federation mark for Devpost and project listings
- `tokens.css` — theme variables and embed helpers
- `splash.html` — lightweight standalone splash/loading screen

`brand/` is the canonical source directory. The matching files under
`source/federation-tv-widget/public/brand/` are the deployment copy consumed by
the public Worker at `watch.drdeeks.xyz`. Keep the two directories identical so
the splash, widget, and documentation use the same visual system.

## Usage

```html
<link rel="stylesheet" href="/brand/tokens.css">
<div class="federation-brand federation-brand--watchtower">...</div>
```

Use `data-federation-theme="relay"` on an embed root to switch a monitor's organization theme.

## Public usage

The live public bundle exposes the same assets at:

```text
https://watch.drdeeks.xyz/brand/federation-f-mark.svg
https://watch.drdeeks.xyz/brand/federation-wordmark.svg
https://watch.drdeeks.xyz/brand/federation-watchtower-thumbnail.jpg
https://watch.drdeeks.xyz/brand/splash.html
```
