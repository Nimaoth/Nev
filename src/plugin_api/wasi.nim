import std/[macros, strutils, os, strformat]
import misc/[custom_logger, util, macro_utils]

import wasmtime

{.push gcsafe, raises: [].}

logCategory "wasi"

type GetMemoryImpl* = proc(caller: ptr CallerT, store: ptr ContextT): WasmMemory {.gcsafe, raises: [].}

type Iovec = object
  data: WasmPtr
  len: uint32

type
  WasiClockId {.size: sizeof(uint32).} = enum
    ## The clock measuring real time. Time value zero corresponds with
    ## 1970-01-01T00:00:00Z.
    Realtime
    ## The store-wide monotonic clock, which is defined as a clock measuring
    ## real time, whose value cannot be adjusted and which cannot have negative
    ## clock jumps. The epoch of this clock is undefined. The absolute time
    ## value of this clock therefore has no meaning.
    Monotonic
    ## The CPU-time clock associated with the current process.
    ProcessCpuTimeId
    ## The CPU-time clock associated with the current thread.
    ThreadCpuTimeId

  WasiTimestamp = uint64

  WasiErrno {.pure, size: sizeof(uint16).} = enum
    ## No error occurred. System call completed successfully.
    Success
    ## Argument list too long.
    Tobig
    ## Permission denied.
    Access
    ## Address in use.
    AddrInUse
    ## Address not available.
    AddrNotAvail
    ## Address family not supported.
    AfNoSupport
    ## Resource unavailable, or operation would block.
    Again
    ## Connection already in progress.
    Already
    ## Bad file descriptor.
    Badf
    ## Bad message.
    BadMsg
    ## Device or resource busy.
    Busy
    ## Operation canceled.
    Canceled
    ## No child processes.
    Child
    ## Connection aborted.
    ConnAborted
    ## Connection refused.
    ConnRefused
    ## Connection reset.
    ConnReset
    ## Resource deadlock would occur.
    Deadlk
    ## Destination address required.
    DestAddrReq
    ## Mathematics argument out of domain of function.
    Dom
    ## Reserved.
    Dquot
    ## File exists.
    Exist
    ## Bad address.
    Fault
    ## File too large.
    Fbig
    ## Host is unreachable.
    HostUnreach
    ## Identifier removed.
    Idrm
    ## Illegal byte sequence.
    Ilseq
    ## Operation in progress.
    InProgress
    ## Interrupted function.
    Intr
    ## Invalid argument.
    Inval
    ## I/O error.
    Io
    ## Socket is connected.
    IsConn
    ## Is a directory.
    IsDir
    ## Too many levels of symbolic links.
    Loop
    ## File descriptor value too large.
    Mfile
    ## Too many links.
    Mlink
    ## Message too large.
    MsgSize
    ## Reserved.
    MultiHop
    ## Filename too long.
    NameTooLong
    ## Network is down.
    NetDown
    ## Connection aborted by network.
    NetReset
    ## Network unreachable.
    NetUnreach
    ## Too many files open in system.
    Nfile
    ## No buffer space available.
    NoBufs
    ## No such device.
    NoDev
    ## No such file or directory.
    NoEnt
    ## Executable file format error.
    NoExec
    ## No locks available.
    NoLck
    ## Reserved.
    NoLink
    ## Not enough space.
    NoMem
    ## No message of the desired type.
    NoMsg
    ## Protocol not available.
    NoProtoopt
    ## No space left on device.
    NoSpc
    ## Function not supported.
    NoSys
    ## The socket is not connected.
    NotConn
    ## Not a directory or a symbolic link to a directory.
    NotDir
    ## Directory not empty.
    NotEmpty
    ## State not recoverable.
    NotRecoverable
    ## Not a socket.
    NotSock
    ## Not supported, or operation not supported on socket.
    NotSup
    ## Inappropriate I/O control operation.
    NotTy
    ## No such device or address.
    Nxio
    ## Value too large to be stored in data type.
    Overflow
    ## Previous owner died.
    OwnerDead
    ## Operation not permitted.
    Perm
    ## Broken pipe.
    Pipe
    ## Protocol error.
    Proto
    ## Protocol not supported.
    ProtoNoSupport
    ## Protocol wrong type for socket.
    Prototype
    ## Result too large.
    Range
    ## Read-only file system.
    Rofs
    ## Invalid seek.
    Spipe
    ## No such process.
    Srch
    ## Reserved.
    Stale
    ## Connection timed out.
    TimedOut
    ## Text file busy.
    TxtBsy
    ## Cross-device link.
    Xdev
    ## Extension: Capabilities insufficient.
    NotCapable

  WasiFiletype {.size: sizeof(uint8).} = enum
    ## The type of the file descriptor or file is unknown or is different from any of the other types specified.
    Unknown,
    ## The file descriptor or file refers to a block device inode.
    BlockDevice,
    ## The file descriptor or file refers to a character device inode.
    CharacterDevice,
    ## The file descriptor or file refers to a directory inode.
    Directory,
    ## The file descriptor or file refers to a regular file inode.
    RegularFile,
    ## The file descriptor or file refers to a datagram socket.
    SocketDgram,
    ## The file descriptor or file refers to a byte-stream socket.
    SocketStream,
    ## The file refers to a symbolic link inode.
    SymbolicLink,

defineBitFlagSized(uint16):
  type WasiFdFlag = enum
    ## Append mode: Data written to the file is always appended to the file's end.
    Append,
    ## Write according to synchronized I/O data integrity completion. Only the data stored in the file is synchronized.
    Dsync,
    ## Non-blocking mode.
    Nonblock,
    ## Synchronized read I/O operations.
    Rsync,
    ## Write according to synchronized I/O file integrity completion. In
    ## addition to synchronizing the data stored in the file, the implementation
    ## may also synchronously update the file's metadata.
    Sync,

defineBitFlagSized(uint64):
  type WasiRight = enum
    ## The right to invoke `fd_datasync`.
    ## If `path_open` is set, includes the right to invoke
    ## `path_open` with `fdflags::dsync`.
    FdDatasync
    ## The right to invoke `fd_read` and `sock_recv`.
    ## If `rights::fd_seek` is set, includes the right to invoke `fd_pread`.
    FdRead
    ## The right to invoke `fd_seek`. This flag implies `rights::fd_tell`.
    FdSeek
    ## The right to invoke `fd_fdstat_set_flags`.
    FdFdstatSetFlags
    ## The right to invoke `fd_sync`.
    ## If `path_open` is set, includes the right to invoke
    ## `path_open` with `fdflags::rsync` and `fdflags::dsync`.
    FdSync
    ## The right to invoke `fd_seek` in such a way that the file offset
    ## remains unaltered (i.e., `whence::cur` with offset zero), or to
    ## invoke `fd_tell`.
    FdTell
    ## The right to invoke `fd_write` and `sock_send`.
    ## If `rights::fd_seek` is set, includes the right to invoke `fd_pwrite`.
    FdWrite
    ## The right to invoke `fd_advise`.
    FdAdvise
    ## The right to invoke `fd_allocate`.
    FdAllocate
    ## The right to invoke `path_create_directory`.
    PathCreateDirectory
    ## If `path_open` is set, the right to invoke `path_open` with `oflags::creat`.
    PathCreateFile
    ## The right to invoke `path_link` with the file descriptor as the
    ## source directory.
    PathLinkSource
    ## The right to invoke `path_link` with the file descriptor as the
    ## target directory.
    PathLinkTarget
    ## The right to invoke `path_open`.
    PathOpen
    ## The right to invoke `fd_readdir`.
    FdReaddir
    ## The right to invoke `path_readlink`.
    PathReadlink
    ## The right to invoke `path_rename` with the file descriptor as the source directory.
    PathRenameSource
    ## The right to invoke `path_rename` with the file descriptor as the target directory.
    PathRenameTarget
    ## The right to invoke `path_filestat_get`.
    PathFilestatGet
    ## The right to change a file's size.
    ## If `path_open` is set, includes the right to invoke `path_open` with `oflags::trunc`.
    ## Note: there is no function named `path_filestat_set_size`. This follows POSIX design,
    ## which only has `ftruncate` and does not provide `ftruncateat`.
    ## While such function would be desirable from the API design perspective, there are virtually
    ## no use cases for it since no code written for POSIX systems would use it.
    ## Moreover, implementing it would require multiple syscalls, leading to inferior performance.
    PathFilestatSetSize
    ## The right to invoke `path_filestat_set_times`.
    PathFilestatSetTimes
    ## The right to invoke `fd_filestat_get`.
    FdFilestatGet
    ## The right to invoke `fd_filestat_set_size`.
    FdFilestatSetSize
    ## The right to invoke `fd_filestat_set_times`.
    FdFilestatSetTimes
    ## The right to invoke `path_symlink`.
    PathSymlink
    ## The right to invoke `path_remove_directory`.
    PathRemoveDirectory
    ## The right to invoke `path_unlink_file`.
    PathUnlinkFile
    ## If `rights::fd_read` is set, includes the right to invoke `poll_oneoff` to subscribe to `eventtype::fd_read`.
    ## If `rights::fd_write` is set, includes the right to invoke `poll_oneoff` to subscribe to `eventtype::fd_write`.
    PollFdReadwrite
    ## The right to invoke `sock_shutdown`.
    SockShutdown
    ## The right to invoke `sock_accept`.
    SockAccept

type
  WasiFdStat {.bycopy.} = object
    ## File type.
    filetype*: WasiFiletype
    ## File descriptor flags.
    flags*: WasiFdFlags
    ## Rights that apply to this file descriptor.
    rightsBase*: WasiRights
    ## Maximum set of rights that may be installed on new file descriptors that
    ## are created through this file descriptor, e.g., through `path_open`.
    rightsInheriting*: WasiRights

static:
  assert sizeof(WasiFdStat) == 24, "witx calculated size"
  assert alignof(WasiFdStat) == 8, "witx calculated align"
  assert offsetof(WasiFdStat, filetype) == 0, "witx calculated offset"
  assert offsetof(WasiFdStat, flags) == 2, "witx calculated offset"
  assert offsetof(WasiFdStat, rightsBase) == 8, "witx calculated offset"
  assert offsetof(WasiFdStat, rightsInheriting) == 16, "witx calculated offset"

proc definePluginWasi*(linker: ptr LinkerT, getMemory: GetMemoryImpl): WasmtimeResult[void] =
  discard linker.defineFuncUnchecked("wasi_snapshot_preview1", "proc_exit", newFunctype([WasmValkind.I32], [])):
    log lvlWarn, "proc_exit: not implemented"
    parameters[0].i32 = WasiErrno.Access.int32

  discard linker.defineFuncUnchecked("wasi_snapshot_preview1", "fd_close", newFunctype([WasmValkind.I32], [WasmValkind.I32])):
    log lvlWarn, "fd_close: not implemented"
    parameters[0].i32 = WasiErrno.Access.int32

  discard linker.defineFuncUnchecked("wasi_snapshot_preview1", "fd_fdstat_get", newFunctype([WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])):
    log lvlWarn, "fd_fdstat_get: not implemented"
    let mem = getMemory(caller, store)
    let fd = parameters[0].i32
    let retPtr = parameters[1].i32.WasmPtr
    let wasiFdStat = mem.getTypedPtr[:WasiFdStat](retPtr)
    wasiFdStat.filetype = WasiFiletype.Unknown
    wasiFdStat.flags = 0.WasiFdFlags
    wasiFdStat.rightsBase = 0.WasiRights
    wasiFdStat.rightsInheriting = 0.WasiRights
    if fd in {1, 2}:
      parameters[0].i32 = WasiErrno.Success.int32
    else:
      parameters[0].i32 = WasiErrno.Access.int32

  var stdout = ""
  var stderr = ""
  discard linker.defineFuncUnchecked("wasi_snapshot_preview1", "fd_write", newFunctype([WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])):
    type Iovec = object
      data: WasmPtr
      len: uint32

    let mem = getMemory(caller, store)

    let fd = parameters[0].i32
    let iovecsPtr = parameters[1].i32.WasmPtr
    let numIovecs = parameters[2].i32
    let pNumWritten = parameters[3].i32.WasmPtr

    let file = case fd
    of 1: stdout.addr
    of 2: stderr.addr
    else:
      mem.write[:uint32](pNumWritten, 0)
      log lvlError, "fd_write: invalid fd" & $fd
      return

    var bytesWritten: uint32 = 0
    for vec in mem.getOpenArray[:Iovec](iovecsPtr, numIovecs):
      if vec.len > 0:
        let data = mem.getRawPtr(vec.data)
        let prevLen = file[].len
        file[].setLen(file[].len + vec.len.int)
        copyMem(file[][prevLen].addr, data, vec.len.int)
        bytesWritten += vec.len.uint32

    case fd
    of 1:
      if file[].endsWith("\n"):
        file[].setLen(file[].len - 1)
      if file[].len > 0:
        log lvlNotice, file[]
    of 2:
      if file[].endsWith("\n"):
        file[].setLen(file[].len - 1)
      if file[].len > 0:
        log lvlError, file[]
    else:
      discard

    file[].setLen(0)

    mem.write[:uint32](pNumWritten, bytesWritten)
    parameters[0].i32 = WasiErrno.Success.int32

  discard linker.defineFuncUnchecked("wasi_snapshot_preview1", "fd_seek", newFunctype([WasmValkind.I32, WasmValkind.I64, WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])):
    log lvlError, "fd_seek: not implemented"
    parameters[0].i32 = WasiErrno.Access.int32

  discard linker.defineFuncUnchecked("wasi_snapshot_preview1", "clock_time_get", newFunctype([WasmValkind.I32, WasmValkind.I64, WasmValkind.I32], [WasmValkind.I32])):
    log lvlWarn, "clock_time_get: not implemented"
    # todo
    let mem = getMemory(caller, store)
    let clockId = parameters[0].i32.WasiClockId
    if clockId != Realtime:
      log lvlWarn, &"clock_time_get: clock {clockId} not implemented"

    let precision = cast[WasiTimestamp](parameters[1].i64)
    let retPtr = parameters[2].i32.WasmPtr
    if retPtr.int != 0:
      # let time = 123456000000000
      let time = 0
      mem.write[:WasiTimestamp](retPtr, time.uint64)

    parameters[0].i32 = WasiErrno.Access.int32

