import std/unittest

import toasty

suite "toasty":
  test "greets by name":
    check greet("Nim") == "hello, Nim"

