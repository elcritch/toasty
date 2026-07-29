import toasty/triad

type ScriptedTriadTransport* = ref object
  replies*: seq[string]
  streams*: seq[seq[string]]
  requests*: seq[string]
  subscriptions*: seq[string]
  requestIndex*: int
  streamIndex*: int
  closedStreams*: int

proc newScriptedTriadTransport*(
    replies: seq[string] = @[], streams: seq[seq[string]] = @[]
): ScriptedTriadTransport =
  ScriptedTriadTransport(replies: replies, streams: streams)

proc asTransport*(fake: ScriptedTriadTransport): TriadTransport =
  let requestImpl = proc(socketPath, request: string): string =
    discard socketPath
    fake.requests.add(request)
    if fake.requestIndex >= fake.replies.len:
      raise newException(IOError, "no scripted Triad reply")
    result = fake.replies[fake.requestIndex]
    inc fake.requestIndex

  let openStreamImpl = proc(socketPath, request: string): TriadStream =
    discard socketPath
    fake.subscriptions.add(request)
    if fake.streamIndex >= fake.streams.len:
      raise newException(IOError, "no scripted Triad stream")
    let lines = fake.streams[fake.streamIndex]
    inc fake.streamIndex
    var lineIndex = 0
    let receiveLineImpl = proc(timeoutMs: int): string =
      discard timeoutMs
      if lineIndex >= lines.len:
        raise newException(IOError, "scripted Triad stream disconnected")
      result = lines[lineIndex]
      inc lineIndex
    let closeImpl = proc() =
      inc fake.closedStreams
    newCallbackStream(receiveLineImpl, closeImpl)

  newCallbackTransport(requestImpl, openStreamImpl)
