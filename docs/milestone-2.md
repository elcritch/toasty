# Milestone 2: Merenda Wayland Backend Audit

This record describes the source audit and FreeBSD runtime proof completed on
2026-07-27 (2026-07-26 UTC).

## Validated revisions

The current FreeBSD build uses these revisions:

```text
Merenda ad66901a2ff9aa894697a39ce582ca5f1a6ecf05
Siwin   9a952099e7ecda08beb07d66d75c0713d40e00cb
Triad   fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9
```

The Siwin revision is from `fix/wayland-initial-configure`. It waits for the
first Wayland configure event before Vulkan surface setup. That synchronous
configure can invoke Merenda's resize callback before `createHostWindow`
returns and Merenda stores the new host. The result was a deterministic null
dereference in `Window.syncNativeGeometry`.

Merenda commit `ad66901a2ff9aa894697a39ce582ca5f1a6ecf05` fixes the
callback's readiness check upstream by accepting a not-yet-assigned host.
`nim merendaWindow` builds `examples/merenda_window.nim` directly from that
revision without a Toasty patch.

## Runtime proof

The original runtime proof used Merenda `784599f9` with the same one-line
readiness guard later committed upstream as `ad66901a`. The example was run in
a private headless River and Triad session so it did not disturb the existing
remote desktop. The window remained alive and Triad reported it on
`HEADLESS-1` with the title and app ID `Toasty Merenda Smoke`. Merenda selected
its Vulkan backend, loaded `VK_KHR_wayland_surface`, selected the AMD Radeon
780M RADV device, and created a five-image mailbox swapchain at 628x704.

After `atlas install -tuk` selected `ad66901a`, the example rebuilt successfully
from a clean Merenda checkout with no local patch.

The captured logs are on the FreeBSD host at:

```text
~/.local/state/toasty/merenda-smoke/20260726T235125Z/
```

This proves ordinary Merenda windows can initialize, render, and remain managed
under the target River/Siwin/Vulkan stack. It does not yet prove a layer-shell
surface or non-1x output scaling.

## Backend capability audit

| Capability | Current support | Finding |
| --- | --- | --- |
| Transparency | Available | Merenda exposes transparent window creation and updates; Siwin's Wayland backend uses an alpha-capable surface and omits the opaque region. A visual alpha test remains. |
| Undecorated window | Not exposed by Merenda | Siwin constructors accept `frameless`, but Merenda's host-window constructor does not pass it through. |
| Output selection | Not available on Wayland | Merenda has no output argument. Siwin accepts a generic `screen` argument but its Wayland path currently ignores it. |
| Scaling | Implemented, partially proven | Siwin binds viewporter and fractional-scale protocols and converts logical and backing coordinates. Merenda also has automatic and environment-controlled UI scaling. The smoke run only covered the headless output's 1x scale. |
| Keyboard and pointer | Implemented | Siwin binds seat, keyboard, and pointer objects. Merenda connects button, motion, scroll, key, text-input, and focus callbacks to NimKit. End-to-end synthetic input against this example remains. |

## Layer-shell audit

Siwin already binds `zwlr_layer_shell_v1` and contains an internal
`LayerSurface` path with layer, anchor, keyboard-interactivity, and
exclusive-zone setters. The generated protocol also includes margins.
However, no public constructor creates that window kind, margins have no Siwin
wrapper, and layer surfaces pass a null `wl_output`, leaving placement to the
compositor. Merenda's FigDraw Siwin bridge always creates a regular window and
exposes none of these layer-shell controls.

The existing code is therefore a partial, dormant implementation rather than a
usable shell-surface API. The next prototype should complete a public Siwin
layer-surface constructor/configuration API, including margins and an optional
output, then expose that capability through the FigDraw Siwin bridge and
Merenda. Toasty should avoid reaching into Siwin private fields through
`privateAccess`; that would make compositor integration depend on backend
internals and would not solve the missing Merenda construction path.

## Next proof

Build a solid Merenda-rendered panel on one River output and verify that it:

1. Uses a layer-shell surface rather than a regular application window.
2. Anchors to the requested edge and honors margins.
3. Reserves space through an exclusive zone.
4. Receives pointer input.
5. Selects a requested output and behaves correctly at non-1x scale.
