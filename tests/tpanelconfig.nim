import std/unittest

import toasty

suite "panel configuration":
  test "defaults describe a top panel":
    let config = defaultPanelConfig(output = 2)

    check config.edge == peTop
    check config.output == 2
    check config.height == 48
    check config.margin == 0
    check config.namespace == "toasty-panel"
    config.validate()

  test "invalid dimensions and namespace are rejected":
    var config = defaultPanelConfig()

    config.output = -1
    expect ValueError:
      config.validate()

    config = defaultPanelConfig()
    config.height = 0
    expect ValueError:
      config.validate()

    config = defaultPanelConfig()
    config.margin = -1
    expect ValueError:
      config.validate()

    config = defaultPanelConfig()
    config.namespace = ""
    expect ValueError:
      config.validate()
