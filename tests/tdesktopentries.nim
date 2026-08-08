import std/[options, unittest]

import toasty

const ExampleDesktopEntry =
  """
[Desktop Entry]
Type=Application
Name=Toasty Browser
Comment=Browse the warm web
Keywords=web;browser;
Exec=toasty-browser --name %c %U %%done
Icon=toasty
Terminal=false
"""

suite "desktop application entries":
  test "parses searchable application metadata":
    let parsed = parseDesktopEntry(ExampleDesktopEntry, "/apps/toasty.desktop")

    check parsed.isSome
    check parsed.get().id == "toasty"
    check parsed.get().name == "Toasty Browser"
    check parsed.get().keywords == @["web", "browser"]

  test "expands desktop field codes into a launch specification":
    let application =
      parseDesktopEntry(ExampleDesktopEntry, "/apps/toasty.desktop").get()
    let spec = application.launchSpec()

    check spec.command == "toasty-browser"
    check spec.arguments == @["--name", "Toasty Browser", "%done"]

  test "rejects hidden and non-application entries":
    check parseDesktopEntry(
      "[Desktop Entry]\nType=Application\nName=Hidden\nExec=hidden\nHidden=true\n",
      "/apps/hidden.desktop",
    ).isNone
    check parseDesktopEntry(
      "[Desktop Entry]\nType=Link\nName=Link\nURL=https://example.com\n",
      "/apps/link.desktop",
    ).isNone
