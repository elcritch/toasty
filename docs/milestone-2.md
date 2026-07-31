# Milestone 2: Merenda Wayland Backend Audit

This record describes the source audit and FreeBSD runtime proof completed on
2026-07-27 (2026-07-26 UTC).

## Original proof revisions

The original FreeBSD proof used these revisions:

```text
Merenda bac6419af62cdaeaba60e774268126fbb346e7a8
FigDraw ad784d79d47bd338ad328c8981a25fc2a03f080e
Siwin   9a952099e7ecda08beb07d66d75c0713d40e00cb
Triad   fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9
```

The Siwin revision is from `fix/wayland-initial-configure`. It waits for the
first Wayland configure event before Vulkan surface setup. That synchronous
configure can invoke Merenda's resize callback before `createHostWindow`
returns and Merenda stores the new host. The result was a deterministic null
dereference in `Window.syncNativeGeometry`.

The Merenda checkout includes the upstream callback readiness fix first
validated at `ad66901a`. Layer-shell support has since moved onto the linked
Siwin, FigDraw, and Merenda `toasty-updates` branches. FigDraw now selects
Siwin's renderer-specific Vulkan or OpenGL layer-surface constructor, and
Toasty no longer applies local UI-backend patches before building.

## Ordinary-window baseline

The original runtime proof used Merenda `784599f9` with the same one-line
readiness guard later committed upstream as `ad66901a`. The example was run in
a private headless River and Triad session so it did not disturb the existing
remote desktop. The window remained alive and Triad reported it on
`HEADLESS-1` with the title and app ID `Toasty Merenda Smoke`. Merenda selected
its Vulkan backend, loaded `VK_KHR_wayland_surface`, selected the AMD Radeon
780M RADV device, and created a five-image mailbox swapchain at 628x704.

After `atlas install -tuk` selected the readiness fix, the example rebuilt
successfully from a clean Merenda checkout with no patch for this ordinary
window path.

The captured logs are on the FreeBSD host at:

```text
~/.local/state/toasty/merenda-smoke/20260726T235125Z/
```

This proved ordinary Merenda windows could initialize, render, and remain
managed under the target River/Siwin/Vulkan stack.

## Layer-shell runtime proof

`nim panelSmoke` was validated in a fresh private headless River session. River
advertised `zwlr_layer_shell_v1` version 4 and mapped namespace `toasty-panel`
on output index 0 (`HEADLESS-1`, 1280x720 at scale 1). The Merenda panel chose
the AMD Radeon 780M RADV Vulkan device and created a five-image mailbox
swapchain at 1280x48.

The panel's 48-pixel exclusive zone reduced each Triad test client's height
from the 628x704 ordinary-window baseline to 628x656. WayVNC 0.10.1 was started
with `--gpu`; an RFB client connected to its 1280x720 framebuffer and sent one
press/release at `(360, 24)`. The panel recorded exactly
`panel-input: click_count=1`.

That input test exposed and fixed a Siwin lifecycle issue: the panel starts
before WayVNC creates its virtual pointer, so the Wayland seat gains pointer
capability after initialization. Siwin now installs pointer, keyboard, and
tablet objects when capabilities appear, while preventing duplicate handlers.

The captured proof is at:

```text
~/.local/state/toasty/session-smoke/20260727T010127Z/
```

## Backend capability audit

| Capability | Current support | Finding |
| --- | --- | --- |
| Transparency | Available | Merenda exposes transparent window creation and updates; Siwin's Wayland backend uses an alpha-capable surface and omits the opaque region. A visual alpha test remains. |
| Undecorated window | Available for the panel | Layer surfaces are compositor-managed shell surfaces rather than decorated application windows. Merenda's ordinary host-window constructor still does not expose Siwin's `frameless` argument. |
| Output selection | Implemented for layer surfaces | Siwin binds `wl_output` globals and the public layer configuration carries a zero-based output index through FigDraw and Merenda. Output 0 was proven; multi-output selection remains to be tested. |
| Scaling | Implemented, partially proven | Siwin binds viewporter and fractional-scale protocols and converts logical and backing coordinates. Merenda also has automatic and environment-controlled UI scaling. The smoke run only covered the headless output's 1x scale. |
| Keyboard and pointer | Implemented; pointer proven | Siwin binds seat, keyboard, and pointer objects, including capabilities added after startup. Merenda connects input callbacks to NimKit. One GPU WayVNC/RFB click produced exactly one panel action. Keyboard interactivity is configurable but the panel intentionally uses `lskNone`. |

## Layer-shell audit

The integration follows the ownership boundaries discovered in the audit:

```text
Toasty PanelConfig
  -> Merenda newLayerSurfaceWindow
  -> FigDraw newSiwinLayerSurfaceWindow(renderer, ...)
  -> Siwin newVulkanLayerSurfaceWindow or newOpenglLayerSurfaceWindow
  -> zwlr_layer_shell_v1
```

Siwin now owns the public platform API for layer, anchors, margins, exclusive
zone, keyboard mode, namespace, and output. FigDraw bridges that API to its
renderer-selected Siwin window. Merenda creates the renderer before the native
layer surface so Vulkan can provide its instance during window creation;
OpenGL uses Siwin's EGL-backed window. Merenda exposes the result as a normal
host-window kind, and Toasty supplies desktop policy through its
backend-independent `PanelConfig`. No dependency private fields are accessed
from Toasty.

The focused example is `examples/merenda_panel.nim`; deterministic validation
of its policy configuration lives in `tests/tpanelconfig.nim`. Reproduce the
complete visual path with:

```sh
nim merendaPanel
TOASTY_SESSION_ONCE=1 nim panelSmoke
```

Milestone 2 is complete. Non-1x scaling and multi-output/hotplug behavior remain
explicit follow-up coverage for the later multi-monitor milestone.
