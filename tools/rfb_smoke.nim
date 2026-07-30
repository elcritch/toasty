import std/[net, os, strutils]

proc fail(message: string) {.noreturn.} =
  stderr.writeLine("rfb-smoke: ", message)
  quit(1)

proc receiveExact(socket: Socket, size: int): string =
  result = newStringOfCap(size)
  while result.len < size:
    let chunk = socket.recv(size - result.len)
    if chunk.len == 0:
      fail("server disconnected")
    result.add(chunk)

proc readU16(value: string, offset = 0): int =
  (value[offset].ord shl 8) or value[offset + 1].ord

proc readU32(value: string, offset = 0): uint32 =
  (value[offset].ord.uint32 shl 24) or (value[offset + 1].ord.uint32 shl 16) or
    (value[offset + 2].ord.uint32 shl 8) or value[offset + 3].ord.uint32

proc addU16(value: var string, number: int) =
  value.add(char((number shr 8) and 0xff))
  value.add(char(number and 0xff))

proc addU32(value: var string, number: uint32) =
  value.add(char((number shr 24) and 0xff))
  value.add(char((number shr 16) and 0xff))
  value.add(char((number shr 8) and 0xff))
  value.add(char(number and 0xff))

proc sendPixelFormat(socket: Socket) =
  var request = "\x00\x00\x00\x00"
  request.add("\x20\x18\x00\x01")
  request.add("\x00\xff\x00\xff\x00\xff")
  request.add("\x10\x08\x00\x00\x00\x00")
  socket.send(request)

proc sendRawEncoding(socket: Socket) =
  var request = "\x02\x00"
  request.addU16(1)
  request.addU32(0)
  socket.send(request)

proc requestFrame(socket: Socket, width, height: int) =
  var request = "\x03\x00"
  request.addU16(0)
  request.addU16(0)
  request.addU16(width)
  request.addU16(height)
  socket.send(request)

proc receiveFrame(socket: Socket, width, height: int): string =
  result = newString(width * height * 3)
  while true:
    let messageType = socket.receiveExact(1)[0].ord
    case messageType
    of 0:
      discard socket.receiveExact(1)
      let rectangleCount = socket.receiveExact(2).readU16()
      for _ in 0 ..< rectangleCount:
        let header = socket.receiveExact(12)
        let
          x = header.readU16(0)
          y = header.readU16(2)
          rectangleWidth = header.readU16(4)
          rectangleHeight = header.readU16(6)
          encoding = header.readU32(8)
        if encoding != 0:
          fail("server selected unsupported encoding " & $encoding)
        let pixels = socket.receiveExact(rectangleWidth * rectangleHeight * 4)
        for row in 0 ..< rectangleHeight:
          for column in 0 ..< rectangleWidth:
            let
              source = (row * rectangleWidth + column) * 4
              destination = ((y + row) * width + x + column) * 3
            result[destination] = pixels[source + 2]
            result[destination + 1] = pixels[source + 1]
            result[destination + 2] = pixels[source]
      return
    of 2:
      discard
    of 3:
      discard socket.receiveExact(3)
      let length = socket.receiveExact(4).readU32().int
      discard socket.receiveExact(length)
    else:
      fail("unsupported server message " & $messageType)

proc sendClick(socket: Socket, x, y: int) =
  for mask in [1, 0]:
    var request = "\x05" & char(mask)
    request.addU16(x)
    request.addU16(y)
    socket.send(request)

if paramCount() notin [3, 5]:
  fail("usage: rfb-smoke HOST PORT SCREENSHOT.ppm [CLICK_X CLICK_Y]")

let
  host = paramStr(1)
  port = Port(paramStr(2).parseInt())
  outputPath = paramStr(3)
  socket = newSocket()

socket.connect(host, port)

let serverVersion = socket.receiveExact(12)
if not serverVersion.startsWith("RFB 003."):
  fail("unexpected protocol greeting")
socket.send("RFB 003.008\n")

let securityCount = socket.receiveExact(1)[0].ord
if securityCount == 0:
  let length = socket.receiveExact(4).readU32().int
  fail(socket.receiveExact(length))
let securityTypes = socket.receiveExact(securityCount)
if '\x01' notin securityTypes:
  fail("server does not offer unauthenticated local access")
socket.send("\x01")
if socket.receiveExact(4).readU32() != 0:
  fail("security handshake failed")

socket.send("\x01")
let serverInit = socket.receiveExact(24)
let
  width = serverInit.readU16(0)
  height = serverInit.readU16(2)
  desktopNameLength = serverInit.readU32(20).int
  desktopName = socket.receiveExact(desktopNameLength)
socket.sendPixelFormat()
socket.sendRawEncoding()
sleep(250)
socket.requestFrame(width, height)
let pixels = socket.receiveFrame(width, height)
writeFile(outputPath, "P6\n" & $width & " " & $height & "\n255\n" & pixels)

if paramCount() == 5:
  socket.sendClick(paramStr(4).parseInt(), paramStr(5).parseInt())

stdout.writeLine(
  "rfb-smoke: desktop=", desktopName, " size=", width, "x", height, " screenshot=",
  outputPath,
)
socket.close()
