## Freedesktop notification service backed by Toasty's notification store.

import notifications

type NotificationDaemon* = ref object
  store*: NotificationStore
  available*: bool
  error*: string
  connection: pointer
  nodeInfo: pointer
  registrationId: uint32
  ownerId: uint32

proc close*(daemon: NotificationDaemon)

when defined(freebsd):
  {.passC: "-I/usr/local/include -pthread -I/usr/local/include/glib-2.0".}
  {.passC: "-I/usr/local/lib/glib-2.0/include".}
  {.passC: "-Wno-incompatible-function-pointer-types".}
  {.passL: "-L/usr/local/lib -lgio-2.0 -lgobject-2.0 -lglib-2.0 -lintl".}

  const
    NotificationBusName = "org.freedesktop.Notifications"
    NotificationObjectPath = "/org/freedesktop/Notifications"
    NotificationInterface = "org.freedesktop.Notifications"
    IntrospectionXml =
      """
<node>
  <interface name="org.freedesktop.Notifications">
    <method name="GetCapabilities">
      <arg direction="out" type="as" name="capabilities"/>
    </method>
    <method name="Notify">
      <arg direction="in" type="s" name="app_name"/>
      <arg direction="in" type="u" name="replaces_id"/>
      <arg direction="in" type="s" name="app_icon"/>
      <arg direction="in" type="s" name="summary"/>
      <arg direction="in" type="s" name="body"/>
      <arg direction="in" type="as" name="actions"/>
      <arg direction="in" type="a{sv}" name="hints"/>
      <arg direction="in" type="i" name="expire_timeout"/>
      <arg direction="out" type="u" name="id"/>
    </method>
    <method name="CloseNotification">
      <arg direction="in" type="u" name="id"/>
    </method>
    <method name="GetServerInformation">
      <arg direction="out" type="s" name="name"/>
      <arg direction="out" type="s" name="vendor"/>
      <arg direction="out" type="s" name="version"/>
      <arg direction="out" type="s" name="spec_version"/>
    </method>
    <signal name="NotificationClosed">
      <arg type="u" name="id"/>
      <arg type="u" name="reason"/>
    </signal>
    <signal name="ActionInvoked">
      <arg type="u" name="id"/>
      <arg type="s" name="action_key"/>
    </signal>
  </interface>
</node>
"""

  type
    GBoolean = cint
    GSize = culong
    GSSize = clong

    GError {.importc: "GError", header: "<gio/gio.h>", bycopy.} = object
      domain: uint32
      code: cint
      message: cstring

    GVariant {.importc: "GVariant", header: "<gio/gio.h>", incompleteStruct.} = object

    GDBusConnection {.
      importc: "GDBusConnection", header: "<gio/gio.h>", incompleteStruct
    .} = object

    GDBusMethodInvocation {.
      importc: "GDBusMethodInvocation", header: "<gio/gio.h>", incompleteStruct
    .} = object

    GDBusNodeInfo {.importc: "GDBusNodeInfo", header: "<gio/gio.h>", incompleteStruct.} = object

    GDBusInterfaceInfo {.
      importc: "GDBusInterfaceInfo", header: "<gio/gio.h>", incompleteStruct
    .} = object

    MethodCallCallback = proc(
      connection: ptr GDBusConnection,
      sender, objectPath, interfaceName, methodName: cstring,
      parameters: ptr GVariant,
      invocation: ptr GDBusMethodInvocation,
      userData: pointer,
    ) {.cdecl.}

    GetPropertyCallback = proc(
      connection: ptr GDBusConnection,
      sender, objectPath, interfaceName, propertyName: cstring,
      error: ptr ptr GError,
      userData: pointer,
    ): ptr GVariant {.cdecl.}

    SetPropertyCallback = proc(
      connection: ptr GDBusConnection,
      sender, objectPath, interfaceName, propertyName: cstring,
      value: ptr GVariant,
      error: ptr ptr GError,
      userData: pointer,
    ): GBoolean {.cdecl.}

    NameCallback =
      proc(connection: ptr GDBusConnection, name: cstring, userData: pointer) {.cdecl.}

    GDBusInterfaceVTable {.
      importc: "GDBusInterfaceVTable", header: "<gio/gio.h>", bycopy
    .} = object
      methodCall {.importc: "method_call".}: MethodCallCallback
      getProperty {.importc: "get_property".}: GetPropertyCallback
      setProperty {.importc: "set_property".}: SetPropertyCallback
      padding: array[8, pointer]

  proc gBusGetSync(
    busType: cint, cancellable: pointer, error: ptr ptr GError
  ): ptr GDBusConnection {.importc: "g_bus_get_sync", header: "<gio/gio.h>".}

  proc gBusOwnNameOnConnection(
    connection: ptr GDBusConnection,
    name: cstring,
    flags: cint,
    acquired, lost: NameCallback,
    userData, destroyNotify: pointer,
  ): uint32 {.importc: "g_bus_own_name_on_connection", header: "<gio/gio.h>".}

  proc gBusUnownName(
    ownerId: uint32
  ) {.importc: "g_bus_unown_name", header: "<gio/gio.h>".}

  proc gDBusNodeInfoNewForXml(
    xml: cstring, error: ptr ptr GError
  ): ptr GDBusNodeInfo {.
    importc: "g_dbus_node_info_new_for_xml", header: "<gio/gio.h>"
  .}

  proc gDBusNodeInfoLookupInterface(
    info: ptr GDBusNodeInfo, name: cstring
  ): ptr GDBusInterfaceInfo {.
    importc: "g_dbus_node_info_lookup_interface", header: "<gio/gio.h>"
  .}

  proc gDBusNodeInfoUnref(
    info: ptr GDBusNodeInfo
  ) {.importc: "g_dbus_node_info_unref", header: "<gio/gio.h>".}

  proc gDBusConnectionRegisterObject(
    connection: ptr GDBusConnection,
    objectPath: cstring,
    interfaceInfo: ptr GDBusInterfaceInfo,
    vtable: ptr GDBusInterfaceVTable,
    userData, destroyNotify: pointer,
    error: ptr ptr GError,
  ): uint32 {.importc: "g_dbus_connection_register_object", header: "<gio/gio.h>".}

  proc gDBusConnectionUnregisterObject(
    connection: ptr GDBusConnection, registrationId: uint32
  ): GBoolean {.importc: "g_dbus_connection_unregister_object", header: "<gio/gio.h>".}

  proc gDBusMethodInvocationReturnValue(
    invocation: ptr GDBusMethodInvocation, parameters: ptr GVariant
  ) {.importc: "g_dbus_method_invocation_return_value", header: "<gio/gio.h>".}

  proc gDBusMethodInvocationReturnDBusError(
    invocation: ptr GDBusMethodInvocation, errorName, message: cstring
  ) {.importc: "g_dbus_method_invocation_return_dbus_error", header: "<gio/gio.h>".}

  proc gDBusConnectionEmitSignal(
    connection: ptr GDBusConnection,
    destination, objectPath, interfaceName, signalName: cstring,
    parameters: ptr GVariant,
    error: ptr ptr GError,
  ): GBoolean {.importc: "g_dbus_connection_emit_signal", header: "<gio/gio.h>".}

  proc gVariantGetChildValue(
    value: ptr GVariant, index: GSize
  ): ptr GVariant {.importc: "g_variant_get_child_value", header: "<gio/gio.h>".}

  proc gVariantGetString(
    value: ptr GVariant, length: ptr GSize
  ): cstring {.importc: "g_variant_get_string", header: "<gio/gio.h>".}

  proc gVariantGetUint32(
    value: ptr GVariant
  ): uint32 {.importc: "g_variant_get_uint32", header: "<gio/gio.h>".}

  proc gVariantGetInt32(
    value: ptr GVariant
  ): int32 {.importc: "g_variant_get_int32", header: "<gio/gio.h>".}

  proc gVariantGetByte(
    value: ptr GVariant
  ): uint8 {.importc: "g_variant_get_byte", header: "<gio/gio.h>".}

  proc gVariantLookupValue(
    dictionary: ptr GVariant, key: cstring, expectedType: pointer
  ): ptr GVariant {.importc: "g_variant_lookup_value", header: "<gio/gio.h>".}

  proc gVariantNewUint32(
    value: uint32
  ): ptr GVariant {.importc: "g_variant_new_uint32", header: "<gio/gio.h>".}

  proc gVariantNewString(
    value: cstring
  ): ptr GVariant {.importc: "g_variant_new_string", header: "<gio/gio.h>".}

  proc gVariantNewStrv(
    values: ptr cstring, length: GSSize
  ): ptr GVariant {.importc: "g_variant_new_strv", header: "<gio/gio.h>".}

  proc gVariantNewTuple(
    children: ptr ptr GVariant, childCount: GSize
  ): ptr GVariant {.importc: "g_variant_new_tuple", header: "<gio/gio.h>".}

  proc gVariantUnref(
    value: ptr GVariant
  ) {.importc: "g_variant_unref", header: "<gio/gio.h>".}

  proc gMainContextIteration(
    context: pointer, mayBlock: GBoolean
  ): GBoolean {.importc: "g_main_context_iteration", header: "<gio/gio.h>".}

  proc gErrorFree(error: ptr GError) {.importc: "g_error_free", header: "<gio/gio.h>".}
  proc gObjectUnref(value: pointer) {.importc: "g_object_unref", header: "<gio/gio.h>".}

  proc errorMessage(error: ptr GError): string =
    if error.isNil or error.message.isNil:
      "unknown GLib error"
    else:
      $error.message

  proc childString(parameters: ptr GVariant, index: int): string =
    let child = gVariantGetChildValue(parameters, index.GSize)
    if child.isNil:
      return
    let value = gVariantGetString(child, nil)
    if not value.isNil:
      result = $value
    gVariantUnref(child)

  proc childUint32(parameters: ptr GVariant, index: int): uint32 =
    let child = gVariantGetChildValue(parameters, index.GSize)
    if child.isNil:
      return
    result = gVariantGetUint32(child)
    gVariantUnref(child)

  proc childInt32(parameters: ptr GVariant, index: int): int32 =
    let child = gVariantGetChildValue(parameters, index.GSize)
    if child.isNil:
      return
    result = gVariantGetInt32(child)
    gVariantUnref(child)

  proc childUrgency(parameters: ptr GVariant): NotificationUrgency =
    let hints = gVariantGetChildValue(parameters, 6)
    if hints.isNil:
      return nuNormal
    let urgency = gVariantLookupValue(hints, "urgency", nil)
    if not urgency.isNil:
      case gVariantGetByte(urgency)
      of 0:
        result = nuLow
      of 2:
        result = nuCritical
      else:
        result = nuNormal
      gVariantUnref(urgency)
    else:
      result = nuNormal
    gVariantUnref(hints)

  proc returnEmpty(invocation: ptr GDBusMethodInvocation) =
    gDBusMethodInvocationReturnValue(invocation, gVariantNewTuple(nil, 0))

  proc returnUint32(invocation: ptr GDBusMethodInvocation, value: uint32) =
    var child = gVariantNewUint32(value)
    gDBusMethodInvocationReturnValue(invocation, gVariantNewTuple(addr child, 1))

  proc returnStrings(invocation: ptr GDBusMethodInvocation, values: openArray[string]) =
    var children: seq[ptr GVariant]
    for value in values:
      children.add(gVariantNewString(value.cstring))
    gDBusMethodInvocationReturnValue(
      invocation, gVariantNewTuple(addr children[0], children.len.GSize)
    )

  proc notificationClosed(daemon: NotificationDaemon, id, reason: uint32) =
    if daemon.connection.isNil:
      return
    var children = [gVariantNewUint32(id), gVariantNewUint32(reason)]
    discard gDBusConnectionEmitSignal(
      cast[ptr GDBusConnection](daemon.connection),
      nil,
      NotificationObjectPath,
      NotificationInterface,
      "NotificationClosed",
      gVariantNewTuple(addr children[0], children.len.GSize),
      nil,
    )

  proc handleMethodCall(
      connection: ptr GDBusConnection,
      sender, objectPath, interfaceName, methodName: cstring,
      parameters: ptr GVariant,
      invocation: ptr GDBusMethodInvocation,
      userData: pointer,
  ) {.cdecl.} =
    discard connection
    discard sender
    discard objectPath
    discard interfaceName
    let daemon = cast[NotificationDaemon](userData)
    case $methodName
    of "GetCapabilities":
      var capabilities = ["body".cstring, "persistence".cstring]
      var child = gVariantNewStrv(addr capabilities[0], capabilities.len.GSSize)
      gDBusMethodInvocationReturnValue(invocation, gVariantNewTuple(addr child, 1))
    of "GetServerInformation":
      invocation.returnStrings(["Toasty", "Toasty", "0.1.0", "1.2"])
    of "Notify":
      let id = daemon.store.add(
        application = parameters.childString(0),
        summary = parameters.childString(3),
        body = parameters.childString(4),
        icon = parameters.childString(2),
        replacesId = parameters.childUint32(1),
        urgency = parameters.childUrgency(),
        timeoutMs = parameters.childInt32(7),
      )
      stderr.writeLine(
        "notification-received: id=",
        id,
        " application=",
        parameters.childString(0),
        " summary=",
        parameters.childString(3),
      )
      invocation.returnUint32(id)
    of "CloseNotification":
      let id = parameters.childUint32(0)
      if daemon.store.close(id):
        daemon.notificationClosed(id, 3)
      invocation.returnEmpty()
    else:
      gDBusMethodInvocationReturnDBusError(
        invocation, "org.freedesktop.DBus.Error.UnknownMethod",
        "Unsupported notification method",
      )

  proc nameAcquired(
      connection: ptr GDBusConnection, name: cstring, userData: pointer
  ) {.cdecl.} =
    discard connection
    discard name
    let daemon = cast[NotificationDaemon](userData)
    daemon.available = true
    daemon.error.setLen(0)

  proc nameLost(
      connection: ptr GDBusConnection, name: cstring, userData: pointer
  ) {.cdecl.} =
    discard connection
    discard name
    let daemon = cast[NotificationDaemon](userData)
    daemon.available = false
    daemon.error = "org.freedesktop.Notifications is unavailable"

  var interfaceVTable = GDBusInterfaceVTable(methodCall: handleMethodCall)

proc startNotificationDaemon*(store: NotificationStore): NotificationDaemon =
  result = NotificationDaemon(store: store)
  when defined(freebsd):
    var error: ptr GError
    let connection = gBusGetSync(2, nil, addr error)
    if connection.isNil:
      result.error = error.errorMessage()
      if not error.isNil:
        gErrorFree(error)
      return
    result.connection = connection

    let nodeInfo = gDBusNodeInfoNewForXml(IntrospectionXml, addr error)
    if nodeInfo.isNil:
      result.error = error.errorMessage()
      if not error.isNil:
        gErrorFree(error)
      gObjectUnref(connection)
      result.connection = nil
      return
    result.nodeInfo = nodeInfo

    let interfaceInfo = gDBusNodeInfoLookupInterface(nodeInfo, NotificationInterface)
    result.registrationId = gDBusConnectionRegisterObject(
      connection,
      NotificationObjectPath,
      interfaceInfo,
      addr interfaceVTable,
      cast[pointer](result),
      nil,
      addr error,
    )
    if result.registrationId == 0:
      result.error = error.errorMessage()
      if not error.isNil:
        gErrorFree(error)
      result.close()
      return

    result.ownerId = gBusOwnNameOnConnection(
      connection,
      NotificationBusName,
      0,
      nameAcquired,
      nameLost,
      cast[pointer](result),
      nil,
    )
    if result.ownerId == 0:
      result.error = "failed to request org.freedesktop.Notifications"
      result.close()
  else:
    result.error = "the notification daemon currently requires FreeBSD GIO"

proc pump*(daemon: NotificationDaemon) =
  when defined(freebsd):
    while gMainContextIteration(nil, 0) != 0:
      discard
    for id in daemon.store.expire():
      daemon.notificationClosed(id, 1)
  else:
    discard daemon

proc close*(daemon: NotificationDaemon) =
  if daemon.isNil:
    return
  when defined(freebsd):
    if daemon.ownerId != 0:
      gBusUnownName(daemon.ownerId)
      daemon.ownerId = 0
    if daemon.registrationId != 0 and not daemon.connection.isNil:
      discard gDBusConnectionUnregisterObject(
        cast[ptr GDBusConnection](daemon.connection), daemon.registrationId
      )
      daemon.registrationId = 0
    if not daemon.nodeInfo.isNil:
      gDBusNodeInfoUnref(cast[ptr GDBusNodeInfo](daemon.nodeInfo))
      daemon.nodeInfo = nil
    if not daemon.connection.isNil:
      gObjectUnref(daemon.connection)
      daemon.connection = nil
  daemon.available = false
