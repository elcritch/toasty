import std/unittest

import toasty

suite "notification center":
  test "adds, replaces, reads, and closes notifications":
    let store = newNotificationStore()
    let first = store.add("Mail", "Hello", "First body", "", createdAt = 10)
    let second = store.add("Chat", "Ping", "Second body", "", createdAt = 11)

    check first == 1
    check second == 2
    check store.items[0].id == second
    check store.unreadCount() == 2

    let replacement = store.add(
      "Mail", "Updated", "Replacement", "", replacesId = first, createdAt = 12
    )
    check replacement == first
    check store.items[1].summary == "Updated"

    store.markAllRead()
    check store.unreadCount() == 0
    check store.close(second)
    check store.items.len == 1

  test "expires only notifications with positive timeouts":
    let store = newNotificationStore()
    let expiring = store.add("Timer", "Done", "", "", timeoutMs = 500, createdAt = 2)
    discard store.add("Sticky", "Keep", "", "", timeoutMs = 0, createdAt = 1)

    check store.expire(now = 2).len == 0
    check store.expire(now = 3) == @[expiring]
    check store.items.len == 1
