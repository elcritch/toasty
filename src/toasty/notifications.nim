## In-memory notification center shared by the D-Bus service and shell UI.

import std/[algorithm, times]

const MaximumNotifications* = 100

type
  NotificationUrgency* = enum
    nuLow
    nuNormal
    nuCritical

  DesktopNotification* = object
    id*: uint32
    application*: string
    summary*: string
    body*: string
    icon*: string
    urgency*: NotificationUrgency
    timeoutMs*: int32
    createdAt*: int64
    read*: bool

  NotificationStore* = ref object
    items*: seq[DesktopNotification]
    nextId*: uint32
    revision*: uint64

proc newNotificationStore*(): NotificationStore =
  NotificationStore(nextId: 1)

proc notificationIndex(store: NotificationStore, id: uint32): int =
  for index, notification in store.items:
    if notification.id == id:
      return index
  -1

proc add*(
    store: NotificationStore,
    application, summary, body, icon: string,
    replacesId = 0'u32,
    urgency = nuNormal,
    timeoutMs = -1'i32,
    createdAt = getTime().toUnix(),
): uint32 =
  var notification = DesktopNotification(
    application: application,
    summary: summary,
    body: body,
    icon: icon,
    urgency: urgency,
    timeoutMs: timeoutMs,
    createdAt: createdAt,
  )
  let replacement = store.notificationIndex(replacesId)
  if replacesId > 0 and replacement >= 0:
    notification.id = replacesId
    store.items[replacement] = notification
    result = replacesId
  else:
    notification.id = store.nextId
    inc store.nextId
    store.items.insert(notification, 0)
    result = notification.id
  if store.items.len > MaximumNotifications:
    store.items.setLen(MaximumNotifications)
  inc store.revision

proc close*(store: NotificationStore, id: uint32): bool =
  let index = store.notificationIndex(id)
  if index < 0:
    return false
  store.items.delete(index)
  inc store.revision
  true

proc markAllRead*(store: NotificationStore) =
  var changed = false
  for notification in store.items.mitems:
    if not notification.read:
      notification.read = true
      changed = true
  if changed:
    inc store.revision

proc clear*(store: NotificationStore) =
  if store.items.len > 0:
    store.items.setLen(0)
    inc store.revision

func unreadCount*(store: NotificationStore): int =
  for notification in store.items:
    if not notification.read:
      inc result

proc expire*(store: NotificationStore, now = getTime().toUnix()): seq[uint32] =
  var index = store.items.high
  while index >= 0:
    let notification = store.items[index]
    if notification.timeoutMs > 0 and
        now * 1000 >= notification.createdAt * 1000 + notification.timeoutMs:
      result.add(notification.id)
      store.items.delete(index)
      inc store.revision
    dec index
  result.reverse()
