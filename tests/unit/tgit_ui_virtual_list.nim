discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/git_ui

import std/unittest
import nuigi/core/vecmath as nuiMath

proc measureGitListText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 8, 20)

proc measureTerminalGitListText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32, 1)

proc changesFrame(view: GitUiView, builder: var UiBuilder,
    input: UiInputSnapshot = UiInputSnapshot()): seq[GitChangesNuiStorage] =
  if builder.backendType == UiBackendType.Terminal:
    builder.defaultStyle.paddingX = 0
    builder.defaultStyle.paddingY = 0
    for style in builder.themeStyles.mitems:
      style.paddingX = 0
      style.paddingY = 0
  discard builder.beginUiFrame(800, 600, input)
  builder.layoutVertical("test-root"):
    discard builder.fillX().fitY()
    view.buildGitChangesList(builder)
    let changesIndex = builder.firstChildIndex(builder.currentNodeIndex)
    for childIndex in changesIndex + 1 ..< builder.frame.nodes.len:
      let storage = builder.nodeStorageGet(builder.frame.nodes[childIndex].addr)
      if storage != nil and storage of GitChangesNuiStorage:
        result.add GitChangesNuiStorage(storage)
  builder.endUiFrame(buildMeshRenderCommands = false)

proc findTextNode(builder: UiBuilder, text: string): int =
  for i in 0 ..< builder.frame.nodes.len:
    if builder.nodeText(i).text == text.uiString:
      return i
  -1

proc historyFrame(view: GitUiView, builder: var UiBuilder,
    panel: CursorPanel): GitChangesNuiStorage =
  discard builder.beginUiFrame(800, 600)
  builder.layoutVertical("history-test-root"):
    discard builder.fillX().fitY()
    view.buildGitHistoryList(builder, panel)
    let listIndex = builder.firstChildIndex(builder.currentNodeIndex)
    result = builder.getOrCreateGitChangesStorage(builder.frame.nodes[listIndex].addr)
  builder.endUiFrame(buildMeshRenderCommands = false)

suite "Git UI virtual changed-file list":
  test "status text uses independent ANSI theme colors and a space before the filename":
    let inserted = rgba(0.2, 0.8, 0.3, 0.6)
    let changed = rgba(0.8, 0.7, 0.2, 0.5)
    let removed = rgba(0.9, 0.2, 0.3, 0.4)
    for status in [Added, Untracked, Modified, Renamed, Conflict, Deleted]:
      let view = GitUiView(changelists: @[
        (vcs: VersionControlSystem(root: "repository"),
          changelist: VCSChangelist(id: "working", description: "Changes",
            files: @[VCSFileInfo(path: "file.nim",
              stagedStatus: status, unstagedStatus: Deleted)]))])
      var builder = newBuilder(measureGitListText)
      builder.themeTextStyle(UiStyleIndexTerminalAnsiGreenText)[].textColor = inserted
      builder.themeTextStyle(UiStyleIndexTerminalAnsiYellowText)[].textColor = changed
      builder.themeTextStyle(UiStyleIndexTerminalAnsiRedText)[].textColor = removed
      discard view.changesFrame(builder)
      let stagedNode = builder.findTextNode($status)
      let unstagedNode = builder.findTextNode("D ")
      let filenameNode = builder.findTextNode("file.nim")
      check stagedNode >= 0
      check unstagedNode >= 0
      check filenameNode >= 0
      let expected = case status
        of Added, Untracked: inserted
        of Deleted: removed
        else: changed
      check builder.nodeText(stagedNode).textColor == expected
      check builder.nodeText(unstagedNode).textColor == removed
      check builder.absoluteNodePos(filenameNode).x >= builder.absoluteNodePos(unstagedNode).x + 16

  test "session expansion state round-trips stable changelist keys":
    let key = "repository\0working\0Working changes"
    let view = GitUiView(commitsExpanded: false, branchesExpanded: true)
    view.changelistsExpanded[key] = false
    view.changelistsExpanded["other-repository\0staged\0Staged changes"] = true
    let data = parseJson($view.saveGitUiSession())
    let restored = GitUiView()
    restored.loadGitUiSession(data)
    check restored.changelistsExpanded == view.changelistsExpanded
    check not restored.commitsExpanded
    check restored.branchesExpanded
    restored.loadGitUiSession(newJObject())
    check restored.changelistsExpanded.len == 0
    check restored.commitsExpanded
    check restored.branchesExpanded

  test "invalid session state does not partially replace expansion state":
    let view = GitUiView(commitsExpanded: false, branchesExpanded: false)
    view.changelistsExpanded["existing"] = false
    view.loadGitUiSession(%*{
      "changelistsExpanded": {"new": true},
      "commitsExpanded": true,
      "branchesExpanded": "invalid"
    })
    check view.changelistsExpanded.len == 1
    check not view.changelistsExpanded["existing"]
    check not view.commitsExpanded
    check not view.branchesExpanded

  test "changelist header is the only label and collapsed lists omit files":
    let vcs = VersionControlSystem(root: "repository")
    let view = GitUiView(changelists: @[
      (vcs: vcs, changelist: VCSChangelist(id: "working", description: "Working changes",
        files: @[VCSFileInfo(path: "file.nim", unstagedStatus: Modified)]))])
    var builder = newBuilder(measureGitListText)
    discard view.changesFrame(builder)
    var labels = 0
    for i in 0 ..< builder.frame.nodes.len:
      if builder.nodeText(i).text == "Working changes".uiString:
        inc labels
    check labels == 1
    view.changelistsExpanded["repository\0working\0Working changes"] = false
    var collapsedBuilder = newBuilder(measureGitListText)
    let storages = view.changesFrame(collapsedBuilder)
    check storages.len == 0
    check collapsedBuilder.findTextNode("file.nim") == -1
    check collapsedBuilder.findTextNode("Working changes") >= 0

  test "commit and branch lists virtualize and cap height at twenty-five text heights":
    let view = GitUiView()
    for i in 0 ..< 10000:
      view.commits.add VCSCommitInfo(id: $i, description: "Commit " & $i)
      view.branches.add "branch-" & $i
    for panel in [Commits, Branches]:
      var builder = newBuilder(measureGitListText)
      var storage = view.historyFrame(builder, panel)
      check storage.listStorage.viewportHeight == 500
      check storage.listStorage.visibleItemRange().last < 30
      check builder.frame.nodes.len < 200
      view.cursor = if panel == Commits:
        UiCursor(panel: Commits, commitIndex: 9999)
      else:
        UiCursor(panel: Branches, branchIndex: 9999)
      for i in 0 ..< 3:
        storage = view.historyFrame(builder, panel)
      check storage.listStorage.visibleItemRange().last == 9999
      check builder.frame.nodes.len < 200

  test "short history lists fit content and preserve filtered branch indexes":
    let view = GitUiView(
      commits: @[VCSCommitInfo(id: "abc", description: "A commit")],
      branches: @["", "main", "", "feature"])
    var builder = newBuilder(measureGitListText)
    let commits = view.historyFrame(builder, Commits)
    check commits.listStorage.viewportHeight > 0
    check commits.listStorage.viewportHeight < 200
    check builder.findTextNode("abc") >= 0
    let branches = view.historyFrame(builder, Branches)
    check branches.branchIndexes == @[1, 3]
    check branches.listStorage.viewportHeight < 200
    check branches.listStorage.visibleItemRange() == (first: 0, last: 1)
    check builder.findTextNode("main") >= 0
    check builder.findTextNode("feature") >= 0

  test "hover actions use stage or unstage symbols and align right":
    for staged in [false, true]:
      let view = GitUiView(changelists: @[
        (vcs: VersionControlSystem(), changelist: VCSChangelist(description: "Changes",
          files: @[VCSFileInfo(path: "file.nim",
            stagedStatus: (if staged: Modified else: None),
            unstagedStatus: (if staged: None else: Modified))]))])
      var builder = newBuilder(measureGitListText)
      discard view.changesFrame(builder)
      check builder.findTextNode("↶") == -1
      let filename = builder.findTextNode("file.nim")
      require filename >= 0
      let mouse = builder.absoluteNodePos(filename) + nuiMath.vec2(2, 2)
      for i in 0 ..< 2:
        discard view.changesFrame(builder, UiInputSnapshot(mouse: mouse))
      let revert = builder.findTextNode("↶")
      let stage = builder.findTextNode(if staged: "−" else: "＋")
      require revert >= 0
      require stage >= 0
      check builder.absoluteNodePos(revert).x > 650
      check builder.absoluteNodePos(stage).x > builder.absoluteNodePos(revert).x
      let buttonMouse = builder.absoluteNodePos(stage) + nuiMath.vec2(2, 2)
      for i in 0 ..< 2:
        discard view.changesFrame(builder, UiInputSnapshot(mouse: buttonMouse))
      check builder.findTextNode("↶") >= 0
      check builder.findTextNode(if staged: "−" else: "＋") >= 0

  test "large changelists build only visible rows and follow selection":
    let view = GitUiView()
    var files: seq[VCSFileInfo]
    for i in 0 ..< 10000:
      files.add VCSFileInfo(path: "src/file" & $i & ".nim", unstagedStatus: Modified)
    view.changelists = @[(vcs: VersionControlSystem(), changelist:
      VCSChangelist(description: "Working tree", files: files))]
    var builder = newBuilder(measureGitListText)
    var storage = view.changesFrame(builder)[0]
    check storage.changelistIndex == 0
    check storage.listStorage.viewportHeight > 0
    check storage.listStorage.viewportHeight == 500
    check builder.frame.nodes.len < 200
    let firstRange = storage.listStorage.visibleItemRange()
    check firstRange.first == 0
    check firstRange.last < 30

    view.cursor = UiCursor(panel: Changelists, changelistIndex: 0, fileIndex: 9999)
    for i in 0 ..< 3:
      storage = view.changesFrame(builder)[0]
    let selectedRange = storage.listStorage.visibleItemRange()
    check selectedRange.first > 9900
    check selectedRange.last == 9999
    check builder.frame.nodes.len < 200

  test "headers and file indexes span multiple and empty changelists":
    let view = GitUiView(changelists: @[
      (vcs: VersionControlSystem(), changelist: VCSChangelist(description: "Empty")),
      (vcs: VersionControlSystem(), changelist: VCSChangelist(description: "Staged",
        files: @[VCSFileInfo(path: "first.nim", stagedStatus: Added)])),
      (vcs: VersionControlSystem(), changelist: VCSChangelist(description: "Working",
        files: @[VCSFileInfo(path: "second.nim", unstagedStatus: Modified)]))])
    var builder = newBuilder(measureGitListText)
    let storages = view.changesFrame(builder)
    check storages.len == 3
    for i, storage in storages:
      check storage.changelistIndex == i
      check storage.listStorage.viewportHeight < 200
      check storage.listStorage.visibleItemRange() ==
        (if i == 0: (first: 0, last: -1) else: (first: 0, last: 0))
    check storages[1].listStorage != storages[2].listStorage

  test "terminal rows use cell sizing":
    let view = GitUiView(changelists: @[
      (vcs: VersionControlSystem(), changelist: VCSChangelist(description: "Working",
        files: @[VCSFileInfo(path: "file.nim", unstagedStatus: Modified)]))])
    var builder = newBuilder(measureTerminalGitListText)
    builder.backendType = UiBackendType.Terminal
    let storage = view.changesFrame(builder)[0]
    check storage.listStorage.viewportHeight == 1

  test "terminal list height is capped at twenty-five default text cells":
    let view = GitUiView()
    var files: seq[VCSFileInfo]
    for i in 0 ..< 100:
      files.add VCSFileInfo(path: "file" & $i & ".nim")
    view.changelists = @[(vcs: VersionControlSystem(), changelist:
      VCSChangelist(description: "Working", files: files))]
    var builder = newBuilder(measureTerminalGitListText)
    builder.backendType = UiBackendType.Terminal
    let storage = view.changesFrame(builder)[0]
    check storage.listStorage.viewportHeight == 25
