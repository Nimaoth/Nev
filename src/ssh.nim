import std/[strformat]
import libssh2
import chronos/transports/stream
import misc/[util]

type
  SSHClient* = ref object of RootObj
    transport*: StreamTransport
    session*: Session

  SCPClient* = object
    session*: Session
    # socket*: AsyncSocket

  SFTPClient* = object
    session*: Session
    # socket*: AsyncSocket
    sftp_session*: Sftp

  SSHChannel* = object
    impl*: libssh2.Channel
    client*: SSHClient

  SSHException* = object of IOError
  AuthenticationException* = object of SSHException
  FileNotFoundException* = object of SSHException

template sshWait*(msg: string, body: untyped): untyped =
  var rc: int
  while true:
    rc = body
    if rc != LIBSSH2_ERROR_EAGAIN:
      break
  if rc != 0:
    echo "Failed to ", msg, ": ", rc

template sshAsyncWait*(msg: string, body: untyped): untyped =
  var rc: int
  while true:
    rc = body
    if rc != LIBSSH2_ERROR_EAGAIN:
      break
    catch sleepAsync(10.milliseconds).await:
      discard
  if rc != 0:
    echo "Failed to ", msg, ": ", rc

proc newSSHClient*(): SSHClient =
  ## Creates a new SSH client and initializes the underlying libssh2 library.
  ## Raises SSHException if initialization fails.
  ##
  ## Returns:
  ##   A new SSHClient instance ready for connections
  result = new SSHClient

proc disconnect*(ssh: SSHClient) =
  ## Cleanly disconnects the SSH session and frees resources.
  ## Should be called when the client is no longer needed.
  ##
  ## It's recommended to use this in a `finally` block or with defer:
  ## ```nim
  ## let client = newSSHClient()
  ## defer: client.disconnect()
  ## ```
  if ssh.session != nil:
    sshWait "disconnect session":
      ssh.session.session_disconnect("")
    discard ssh.session.session_free()
    ssh.session = nil

  if ssh.transport != nil:
    ssh.transport.close()

# proc connect*(s: SSHClient, hostname: string, username: string, port = Port(22), password = "", privKey = "", pubKey = "", useAgent = false) {.async.} =
#   ## Establishes an SSH connection to a remote host with the specified authentication method.
#   ##
#   ## Parameters:
#   ##   hostname: The remote host to connect to
#   ##   username: The username for authentication
#   ##   port: The SSH port (default: 22)
#   ##   password: Optional password for password auth or private key passphrase
#   ##   privKey: Path to private key file for public key authentication
#   ##   pubKey: Path to public key file (optional with private key)
#   ##   useAgent: Whether to attempt authentication using SSH agent
#   ##
#   ## Authentication Methods:
#   ## * Password: Set `password` parameter
#   ## * Public Key: Set `privKey` and optionally `pubKey`
#   ## * SSH Agent: Set `useAgent` to true
#   ##
#   ## Raises:
#   ##   SSHException: On connection or handshake failure
#   ##   AuthenticationException: On authentication failure
#   s.socket = newAsyncSocket()
#   s.socket.setSockOpt(OptNoDelay, true, level = 6)
#   await s.socket.connect(hostname, port)
#   s.session = initSession()
#   s.session.setBlocking(false)
#   s.session.handshake(s.socket.getFd())

#   if useAgent:
#     let agent = initAgent(s.session)
#     agent.connect()
#     agent.listIdentities()

#     for identity in agent.identities:
#       if agent.authenticate(identity, username):
#         break
#     agent.close_agent()
#   else:
#     if privKey.len != 0:
#       discard s.session.authPublicKey(username, privKey, pubKey, password)
    # else:
    #   discard s.session.authPassword(username, password)

proc getLastError*(session: Session): (string, int) =
  var
    errmsg: cstring
    errlen: cint
  let errcode = session.session_last_error(addr errmsg, addr errlen, 0)
  result = ($errmsg, errcode.int)

proc getLastErrorMessage*(session: Session): string =
  let (msg, code) = getLastError(session)
  result = &"{msg} ({code})"

proc initChannel*(ssh: SSHClient): SSHChannel =
  ## Establish a generic session channel
  result.client = ssh
  while true:
    result.impl = ssh.session.channel_open_session()
    if result.impl == nil and ssh.session.session_last_errno() == LIBSSH2_ERROR_EAGAIN:
      discard
      # discard ssh.waitsocket()
    else:
      break
  if result.impl == nil:
    raise newException(SSHException, ssh.session.getLastErrorMessage())

proc setEnv*(channel: SSHChannel, name, value: string): bool {.inline.} =
  ## Set an environment variable on the channel
  return channel.impl.channel_set_env(name, value) != -1

proc exec*(channel: SSHChannel, command: string): bool =
  var rc: cint
  while true:
    rc = channel.impl.channel_exec(command)
    if rc != LIBSSH2_ERROR_EAGAIN:
      break
  return rc == 0

proc close*(channel: SSHChannel) =
  if channel.impl != nil:
    var rc: cint
    while true:
      rc = channel.impl.channel_close()
      if rc == LIBSSH2_ERROR_EAGAIN:
        # discard waitsocket(channel.client)
        discard
      else:
        break

proc getExitStatus*(channel: SSHChannel): int {.inline.} =
  channel.impl.channel_get_exit_status()

proc free*(channel: SSHChannel) =
  if channel.impl != nil:
    discard channel.impl.channel_free()
