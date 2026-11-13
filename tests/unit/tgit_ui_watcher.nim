discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/git_ui

import std/unittest
import vfs_local

type WatchCallback = proc(events: seq[PathEvent]) {.gcsafe, raises: [].}

var watchedDirectories: Table[string, WatchCallback]
var directories: Table[string, seq[string]]

proc testWatch(self: VFS, path: string, cb: WatchCallback): Id {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    watchedDirectories[path] = cb
  newId()

proc testListing(self: VFS, path: string): Future[vfs.DirectoryListing] {.async: (raises: []).} =
  {.cast(gcsafe).}:
    return vfs.DirectoryListing(folders: directories.getOrDefault(path))

proc testFileKind(self: VFS, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  {.cast(gcsafe).}:
    if path in directories:
      return FileKind.Directory.some
    return FileKind.File.some

suite "Git UI repository watcher":
  var view: GitUiView
  var root: string

  setup:
    watchedDirectories.clear()
    directories.clear()
    let vfs = VFS.new()
    vfs.getMutUnsafe.watchImpl = testWatch
    vfs.getMutUnsafe.getDirectoryListingImpl = testListing
    vfs.getMutUnsafe.getFileKindImpl = testFileKind
    view = GitUiView(vcsService: VCSService(vfs: vfs))
    view.refreshTask = newDelayedTask(60000, false, false, proc() = discard)
    root = vfs.normalize("watcher-test-repository")
    directories[root] = @["src"]
    directories[root // "src"] = @["nested"]
    directories[root // "src" // "nested"] = @[]

  teardown:
    view.refreshTask.deinit()

  test "watches the entire directory tree without duplicate registrations":
    waitFor view.watchRepositoryDirectory(root)
    check watchedDirectories.len == 3
    check root // "src" // "nested" in watchedDirectories
    waitFor view.watchRepositoryDirectory(root)
    check watchedDirectories.len == 3

  test "never watches Git metadata directories or their descendants":
    directories[root].add ".git"
    directories[root // ".git"] = @["objects"]
    directories[root // ".git" // "objects"] = @[]
    waitFor view.watchRepositoryDirectory(root)
    check watchedDirectories.len == 3
    check root // ".git" notin watchedDirectories
    waitFor view.watchCreatedDirectories(root, @[
      (name: ".git", action: FileEventAction.Create, newName: "")])
    check watchedDirectories.len == 3

  test "nested modifications schedule a refresh and empty batches do not":
    waitFor view.watchRepositoryDirectory(root)
    watchedDirectories[root // "src" // "nested"](@[])
    check not view.refreshPending
    watchedDirectories[root // "src" // "nested"](@[
      (name: "file.nim", action: FileEventAction.Modify, newName: "")])
    waitFor sleepAsync(chronos.milliseconds(20))
    check view.refreshPending
    check view.refreshTask.isActive

  test "created and moved-in directories gain watches for their descendants":
    waitFor view.watchRepositoryDirectory(root)
    directories[root // "new"] = @["child"]
    directories[root // "new" // "child"] = @[]
    waitFor view.watchCreatedDirectories(root, @[
      (name: "new", action: FileEventAction.Create, newName: "")])
    check root // "new" // "child" in watchedDirectories
    directories[root // "moved"] = @["nested"]
    directories[root // "moved" // "nested"] = @[]
    waitFor view.watchCreatedDirectories(root, @[
      (name: "old", action: FileEventAction.Rename, newName: "moved")])
    check root // "moved" // "nested" in watchedDirectories

  test "recreated directories are rescanned without duplicate watches":
    waitFor view.watchRepositoryDirectory(root)
    directories[root // "src"].add "new-child"
    directories[root // "src" // "new-child"] = @[]
    waitFor view.watchCreatedDirectories(root, @[
      (name: "src", action: FileEventAction.Create, newName: "")])
    check root // "src" // "new-child" in watchedDirectories
    check watchedDirectories.len == 4

  test "non-Git repositories are not watched":
    view.watchRepository(VersionControlSystem(name: "Perforce", root: root))
    check watchedDirectories.len == 0
    check not view.refreshPending

  test "changes during a refresh queue another pass without starting a concurrent task":
    view.refreshing = true
    view.scheduleRepositoryRefresh()
    check view.refreshPending
    check not view.refreshTask.isActive

suite "Git UI local VFS watcher":
  test "ignored log writes do not cause refresh feedback while tracked files still refresh":
    let root = getTempDir() // ("nev-git-ui-events-" & $newId())
    createDir(root // "logs")
    defer:
      waitFor sleepAsync(chronos.milliseconds(500))
      removeDir(root)
    require execCmdEx("git init --quiet " & quoteShell(root)).exitCode == 0
    writeFile(root // ".gitignore", "*.log\nignored/\n")
    writeFile(root // "tracked.log", "tracked")
    require execCmdEx("git -C " & quoteShell(root) &
      " add --force tracked.log").exitCode == 0
    let localVfs = newVFSLocal()
    let view = GitUiView(vcsService: VCSService(vfs: localVfs))
    view.refreshTask = newDelayedTask(60000, false, false, proc() = discard)
    defer: view.refreshTask.deinit()
    waitFor view.watchRepositoryDirectory(root, root = root)

    for i in 0 ..< 3:
      writeFile(root // "logs" // "messages.log", "refresh log " & $i)
      waitFor sleepAsync(chronos.milliseconds(500))
      check not view.refreshPending
      check not view.refreshTask.isActive

    waitFor view.handleRepositoryChanges(root, @[
      (name: ".git/index", action: FileEventAction.Modify, newName: "")], root)
    check not view.refreshPending
    createDir(root // "ignored")
    waitFor view.handleRepositoryChanges(root, @[
      (name: "ignored", action: FileEventAction.Create, newName: "")], root)
    check not view.refreshPending
    waitFor view.handleRepositoryChanges(root, @[
      (name: "tracked.log", action: FileEventAction.Modify, newName: "")], root)
    check view.refreshPending
    view.refreshPending = false
    waitFor view.handleRepositoryChanges(root, @[
      (name: "source.nim", action: FileEventAction.Rename, newName: "source.log")], root)
    check view.refreshPending
    view.refreshPending = false
    waitFor view.handleRepositoryChanges(root, @[
      (name: "source.log", action: FileEventAction.Rename, newName: "source.nim")], root)
    check view.refreshPending

  test "Git ignore rules filter existing and newly created directories":
    let root = getTempDir() // ("nev-git-ui-ignore-" & $newId())
    createDir(root)
    defer:
      waitFor sleepAsync(chronos.milliseconds(500))
      removeDir(root)
    let initialized = execCmdEx("git init --quiet " & quoteShell(root))
    require initialized.exitCode == 0
    writeFile(root // ".gitignore", "ignored/\nspace dir/\n*.cache/\n!keep.cache/\n")
    writeFile(root // ".git" // "info" // "exclude", "excluded/\n")
    for directory in ["ignored/child", "space dir", "drop.cache", "keep.cache",
        "excluded", "src/drop", "src/keep"]:
      createDir(root // directory)
    writeFile(root // "src" // ".gitignore", "drop/\n")

    let localVfs = newVFSLocal()
    let view = GitUiView(vcsService: VCSService(vfs: localVfs))
    view.refreshTask = newDelayedTask(60000, false, false, proc() = discard)
    defer: view.refreshTask.deinit()
    waitFor view.watchRepositoryDirectory(root, root = root)
    check view.repositoryWatches.len == 4
    for directory in [".git", "ignored", "ignored/child", "space dir",
        "drop.cache", "excluded", "src/drop"]:
      check localVfs.normalize(root // directory) notin view.repositoryWatches
    for directory in ["keep.cache", "src", "src/keep"]:
      check localVfs.normalize(root // directory) in view.repositoryWatches

    createDir(root // "new.cache")
    createDir(root // "new-folder" // "nested")
    waitFor view.watchCreatedDirectories(root, @[
      (name: "new.cache", action: FileEventAction.Create, newName: ""),
      (name: "new-folder", action: FileEventAction.Rename, newName: "new-folder")],
      root = root)
    check localVfs.normalize(root // "new.cache") notin view.repositoryWatches
    check localVfs.normalize(root // "new-folder" // "nested") in view.repositoryWatches

  test "observes nested writes and registers newly created folders":
    let root = getTempDir() // ("nev-git-ui-watch-" & $newId())
    let nested = root // "nested"
    let created = root // "created"
    let filename = nested // "file.txt"
    createDir(nested)
    let localVfs = newVFSLocal()
    let view = GitUiView(vcsService: VCSService(vfs: localVfs))
    view.refreshTask = newDelayedTask(60000, false, false, proc() = discard)
    defer:
      view.refreshTask.deinit()
      removeFile(filename)
      removeDir(created)
      removeDir(nested)
      removeDir(root)
    waitFor view.watchRepositoryDirectory(root)
    writeFile(filename, "changed")
    waitFor sleepAsync(chronos.milliseconds(500))
    check view.refreshPending
    view.refreshPending = false
    createDir(created)
    waitFor sleepAsync(chronos.milliseconds(500))
    check localVfs.normalize(created) in view.repositoryWatches
    check view.refreshPending
