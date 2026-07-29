import std/[nativesockets, net, os]

const
  DefaultTriadRequestTimeoutMs* = 5000
  DefaultTriadMaxLineBytes* = 256 * 1024

type
  TriadStream* = ref object
    receiveLineImpl: proc(timeoutMs: int): string {.closure.}
    closeImpl: proc() {.closure.}

  TriadTransport* = ref object
    requestImpl: proc(socketPath, request: string): string {.closure.}
    openStreamImpl: proc(socketPath, request: string): TriadStream {.closure.}

proc newCallbackTransport*(
    request: proc(socketPath, request: string): string {.closure.},
    openStream: proc(socketPath, request: string): TriadStream {.closure.},
): TriadTransport =
  TriadTransport(requestImpl: request, openStreamImpl: openStream)

proc newCallbackStream*(
    receiveLine: proc(timeoutMs: int): string {.closure.},
    close: proc() {.closure.} = nil,
): TriadStream =
  TriadStream(receiveLineImpl: receiveLine, closeImpl: close)

proc request*(transport: TriadTransport, socketPath, request: string): string =
  if transport.isNil or transport.requestImpl.isNil:
    raise newException(IOError, "Triad request transport is unavailable")
  transport.requestImpl(socketPath, request)

proc openStream*(transport: TriadTransport, socketPath, request: string): TriadStream =
  if transport.isNil or transport.openStreamImpl.isNil:
    raise newException(IOError, "Triad stream transport is unavailable")
  transport.openStreamImpl(socketPath, request)

proc receiveLine*(stream: TriadStream, timeoutMs = -1): string =
  if stream.isNil or stream.receiveLineImpl.isNil:
    raise newException(IOError, "Triad event stream is unavailable")
  stream.receiveLineImpl(timeoutMs)

proc close*(stream: TriadStream) =
  if not stream.isNil and not stream.closeImpl.isNil:
    stream.closeImpl()

proc defaultTriadSocketPath*(): string =
  let configured = getEnv("TRIAD_SOCKET")
  if configured.len > 0:
    configured
  else:
    getEnv("XDG_RUNTIME_DIR", "/tmp") / "triad.sock"

when defined(posix):
  proc connectTriadSocket(socketPath: string): Socket =
    result = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
    try:
      result.connectUnix(socketPath)
    except CatchableError:
      result.close()
      raise

proc newUnixTriadTransport*(
    requestTimeoutMs = DefaultTriadRequestTimeoutMs
): TriadTransport =
  when defined(posix):
    let requestImpl = proc(socketPath, request: string): string =
      let socket = connectTriadSocket(socketPath)
      try:
        socket.send(request & "\n")
        result = socket.recvLine(
          timeout = requestTimeoutMs, maxLength = DefaultTriadMaxLineBytes
        )
        if result.len == 0:
          raise newException(IOError, "Triad closed the request connection")
      finally:
        socket.close()

    let openStreamImpl = proc(socketPath, request: string): TriadStream =
      let socket = connectTriadSocket(socketPath)
      try:
        socket.send(request & "\n")
      except CatchableError:
        socket.close()
        raise
      var closed = false
      let receiveLineImpl = proc(timeoutMs: int): string =
        if closed:
          raise newException(IOError, "Triad event stream is closed")
        result =
          socket.recvLine(timeout = timeoutMs, maxLength = DefaultTriadMaxLineBytes)
        if result.len == 0:
          raise newException(IOError, "Triad event stream disconnected")
      let closeImpl = proc() =
        if not closed:
          closed = true
          socket.close()
      newCallbackStream(receiveLineImpl, closeImpl)

    result = newCallbackTransport(requestImpl, openStreamImpl)
  else:
    raise newException(IOError, "Triad Unix sockets require a POSIX platform")
