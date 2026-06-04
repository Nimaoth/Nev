#use input_handler command_service layout
import std/[options]

const currentSourcePath2 = currentSourcePath()
include module_base

# DLL API

# Nice wrappers

# Implementation
when implModule and defined(profiler):
  import std/[algorithm, tables, json, strformat, strutils, sugar, os, atomics]
  import std/times except milliseconds
  import misc/[custom_async, myjsonutils, util, timer, event]
  import ui/node
  import misc/[render_command]
  import theme
  import vmath, chroma
  import service, view, layout/layout, input_handler/input_handler, command_service, platform

  import prof

  import debug_allocator

  const
    maxProfilerSnapshots = 1024 * 32
    snapshotInterval = 100
    leakMinAgeSeconds = 5.0
    leakMinTrackedSize = 4 * 1
    stackChartMinTotalSize = 200 * 1024
    stackChartMinAllocationCount = 500
    stackChartMinTotalAllocationCount = 40000
    stackChartMinAllocationsPerSecond = 50.0
    stackHistoryEntries = 50
    leakMaxResults = 10
    leakScanBatchPerTick = 10
    initialEventHandlersCapacity = 8
    initialAllocationsCapacity = 1024 * 1024
    initialLeakCandidateCapacity = 16 * 1024
    initialLeakResultsCapacity = leakMaxResults * 4
    initialStackAllocationsCapacity = 32 * 1024
    initialSnapshotAggregateCapacity = 1024
    initialTagSortScratchCapacity = 64
    initialRenderCommandPoolCapacity = 64

  type
    SnapshotSeriesKind* = enum
      sskTotal
      sskUntagged
      sskTag
      sskAllocatorEvents

    StackSortMode* = enum
      ssmTotalSize
      ssmAllocationCount
      ssmTotalAllocations
      ssmAllocationsPerSecond

    MemorySnapshot* = object
      timestamp*: float
      allocatedBytes*: int
      globalAllocatedBytes*: int
      untaggedAllocatedBytes*: int
      allocatorEventsProcessed*: int
      tagAllocatedBytes*: array[64, int]

    TrackedAllocation* = object
      tagMask*: uint64
      usableSize*: int
      allocTimestamp*: float64
      threadId*: uint64
      returnAddressHash*: uint64
      stackTrace*: cstring

    PotentialLeak* = object
      ptrValue*: uint64
      tagMask*: uint64
      usableSize*: int
      ageSeconds*: float64
      threadId*: uint64
      returnAddressHash*: uint64
      stackTrace*: cstring
      score*: float64

    StackAllocationSummary* = object
      returnAddressHash*: uint64
      stackTrace*: cstring
      totalAllocatedSize*: int
      allocationCount*: int
      totalAllocationCount*: int
      allocationsPerSecond*: float64
      baselineSize*: int
      baselineCount*: int
      baselineTotalAllocationCount*: int
      baselineAllocationsPerSecond*: float64
      sizeHistory*: array[stackHistoryEntries, int]
      countHistory*: array[stackHistoryEntries, int]
      totalAllocationCountHistory*: array[stackHistoryEntries, int]
      sampleTimeHistory*: array[stackHistoryEntries, float64]
      historyLen*: int
      historyWriteCursor*: int

    ProfilerView* = ref object of View
      eventHandlers*: Table[string, EventHandler]
      snapshotStart*: int
      snapshotLen*: int
      hoveredSnapshotLogicalIndex*: int = -1
      hoveredSeriesKind*: SnapshotSeriesKind = sskTotal
      hoveredSeriesTagBit*: int = -1
      baselineSnapshotN*: int = 0
      baselineReferenceCaptured*: bool
      baselineReferenceTotal*: int
      baselineReferenceUntagged*: int
      baselineReferenceAllocatorEvents*: int
      baselineReferenceTags*: array[64, int]
      snapshotHistory*: array[maxProfilerSnapshots, MemorySnapshot]
      allocatorEventsSinceLastSnapshot: int
      lastSnapshotTimestamp: float
      allocatorEventReadIndex*: uint64
      allocationsByPtr*: Table[uint64, TrackedAllocation]
      potentialLeakCandidates*: seq[uint64]
      potentialLeakCandidateIndices*: Table[uint64, int]
      potentialLeakScanCursor*: int
      potentialLeakCycleResults*: seq[PotentialLeak]
      cachedPotentialLeaks*: seq[PotentialLeak]
      tagAllocatedSizes*: array[64, int]
      globalAllocatedSize*: int
      untaggedAllocatedSize*: int
      leakVisibleTags*: set[DaTag]
      activeTabIndex*: int
      tabScrollOffsets*: array[2, float]
      stackAllocationsByHash*: Table[uint64, StackAllocationSummary]
      hoveredStackReturnAddressHash*: uint64
      hoveredPotentialLeakPtr*: uint64
      stackSortMode*: StackSortMode = ssmTotalSize
      snapshotAggregatedValues*: seq[int]
      stackScratch*: seq[StackAllocationSummary]
      sortedTagBitsScratch*: seq[int]
      renderCommandPool*: seq[ref RenderCommands]
      renderCommandPoolCursor*: int

  var gProfiler: ProfilerView

  proc currentTimeSeconds(): float64 =
    getTime().toUnixFloat()

  proc addSnapshot(self: ProfilerView, allocatedBytes: int, allocatorEventsProcessed: int = 0) =
    let snapshot = MemorySnapshot(
      timestamp: currentTimeSeconds(),
      allocatedBytes: allocatedBytes,
      globalAllocatedBytes: self.globalAllocatedSize,
      untaggedAllocatedBytes: self.untaggedAllocatedSize,
      allocatorEventsProcessed: max(0, allocatorEventsProcessed),
      tagAllocatedBytes: self.tagAllocatedSizes,
    )

    if self.snapshotLen < maxProfilerSnapshots:
      let idx = (self.snapshotStart + self.snapshotLen) mod maxProfilerSnapshots
      self.snapshotHistory[idx] = snapshot
      inc self.snapshotLen
    else:
      self.snapshotHistory[self.snapshotStart] = snapshot
      self.snapshotStart = (self.snapshotStart + 1) mod maxProfilerSnapshots

  proc latestSnapshotBytes(self: ProfilerView): int =
    if self.snapshotLen == 0:
      return 0

    let idx = (self.snapshotStart + self.snapshotLen - 1) mod maxProfilerSnapshots
    return self.snapshotHistory[idx].allocatedBytes

  proc previousSnapshotBytes(self: ProfilerView): int =
    if self.snapshotLen < 2:
      return 0

    let idx = (self.snapshotStart + self.snapshotLen - 2) mod maxProfilerSnapshots
    return self.snapshotHistory[idx].allocatedBytes

  proc snapshotAt(self: ProfilerView, logicalIndex: int): MemorySnapshot =
    let idx = (self.snapshotStart + logicalIndex) mod maxProfilerSnapshots
    return self.snapshotHistory[idx]

  proc forceSetBaselineReference(self: ProfilerView) =
    if self.snapshotLen <= 0:
      return
    let latestSnapshot = self.snapshotAt(self.snapshotLen - 1)
    self.baselineReferenceTotal = latestSnapshot.globalAllocatedBytes
    self.baselineReferenceUntagged = latestSnapshot.untaggedAllocatedBytes
    self.baselineReferenceAllocatorEvents = latestSnapshot.allocatorEventsProcessed
    self.baselineReferenceTags = latestSnapshot.tagAllocatedBytes
    self.baselineReferenceCaptured = true
    for _, summary in mpairs(self.stackAllocationsByHash):
      summary.baselineSize = summary.totalAllocatedSize
      summary.baselineCount = summary.allocationCount
      summary.baselineTotalAllocationCount = summary.totalAllocationCount
      summary.baselineAllocationsPerSecond = summary.allocationsPerSecond

  proc tryCaptureBaselineReference(self: ProfilerView) =
    if self.baselineReferenceCaptured or self.snapshotLen <= 0:
      return

    let baselineLogicalIndex =
      if self.baselineSnapshotN <= 1:
        0
      elif self.snapshotLen >= self.baselineSnapshotN:
        self.baselineSnapshotN - 1
      else:
        return

    let baselineSnapshot = self.snapshotAt(baselineLogicalIndex)
    self.baselineReferenceTotal = baselineSnapshot.globalAllocatedBytes
    self.baselineReferenceUntagged = baselineSnapshot.untaggedAllocatedBytes
    self.baselineReferenceAllocatorEvents = baselineSnapshot.allocatorEventsProcessed
    self.baselineReferenceTags = baselineSnapshot.tagAllocatedBytes
    self.baselineReferenceCaptured = true

  proc snapshotSeriesValue(snapshot: MemorySnapshot, seriesKind: SnapshotSeriesKind, tagBit: int): int =
    case seriesKind
    of sskTotal:
      return snapshot.globalAllocatedBytes
    of sskUntagged:
      return snapshot.untaggedAllocatedBytes
    of sskAllocatorEvents:
      return snapshot.allocatorEventsProcessed
    of sskTag:
      if tagBit in 0..<64:
        return snapshot.tagAllocatedBytes[tagBit]
      return 0

  proc averagedSnapshotSeriesValue(self: ProfilerView, seriesKind: SnapshotSeriesKind, tagBit: int, logicalStart: float, logicalEnd: float): int =
    if self.snapshotLen <= 0:
      return 0

    let startPos = clamp(logicalStart, 0.0, self.snapshotLen.float)
    let endPos = clamp(logicalEnd, startPos, self.snapshotLen.float)
    if endPos <= startPos:
      return 0

    var weightedSum = 0.0
    var totalWeight = 0.0
    var idx = clamp(int(startPos), 0, self.snapshotLen - 1)

    while idx < self.snapshotLen:
      let sampleStart = idx.float
      let sampleEnd = sampleStart + 1.0
      let overlapStart = max(startPos, sampleStart)
      let overlapEnd = min(endPos, sampleEnd)
      let overlap = overlapEnd - overlapStart

      if overlap > 0:
        let sampleValue = max(0, snapshotSeriesValue(self.snapshotAt(idx), seriesKind, tagBit))
        weightedSum += sampleValue.float * overlap
        totalWeight += overlap

      if sampleEnd >= endPos:
        break
      inc idx

    if totalWeight <= 0:
      return 0
    return int((weightedSum / totalWeight) + 0.5)

  proc seriesLabel(seriesKind: SnapshotSeriesKind, tagBit: int): string =
    case seriesKind
    of sskTotal:
      return "Total"
    of sskUntagged:
      return "Untagged"
    of sskAllocatorEvents:
      return "Allocator Events/Update"
    of sskTag:
      if tagBit in ord(low(DaTag))..ord(high(DaTag)):
        return $DaTag(tagBit)
      return fmt"Tag[{tagBit}]"

  proc baselineSeriesValue(self: ProfilerView, seriesKind: SnapshotSeriesKind, tagBit: int, fallback: int): int =
    if not self.baselineReferenceCaptured:
      return fallback

    case seriesKind
    of sskTotal:
      return self.baselineReferenceTotal
    of sskUntagged:
      return self.baselineReferenceUntagged
    of sskAllocatorEvents:
      return self.baselineReferenceAllocatorEvents
    of sskTag:
      if tagBit in 0..<64:
        return self.baselineReferenceTags[tagBit]
      return fallback

  proc applyTagDelta(self: ProfilerView, tagMask: uint64, delta: int) =
    for bit in 0..<64:
      if ((tagMask shr bit) and 1'u64) != 0:
        self.tagAllocatedSizes[bit] += delta

  proc applyAllocationDelta(self: ProfilerView, tagMask: uint64, delta: int) =
    self.globalAllocatedSize += delta
    if tagMask == 0:
      self.untaggedAllocatedSize += delta
    self.applyTagDelta(tagMask, delta)

  proc resetAllocationTracking(self: ProfilerView) =
    self.allocationsByPtr.clear()
    self.potentialLeakCandidates.setLen(0)
    self.potentialLeakCandidateIndices.clear()
    self.potentialLeakScanCursor = 0
    self.potentialLeakCycleResults.setLen(0)
    self.cachedPotentialLeaks.setLen(0)
    self.stackAllocationsByHash.clear()
    self.globalAllocatedSize = 0
    self.untaggedAllocatedSize = 0
    for bit in 0..<64:
      self.tagAllocatedSizes[bit] = 0

  proc applyStackAllocationDelta(self: ProfilerView, returnAddressHash: uint64, stackTrace: cstring, sizeDelta: int, allocationDelta: int, totalAllocationDelta: int = 0) =
    if returnAddressHash == 0 or (sizeDelta == 0 and allocationDelta == 0):
      return

    if self.stackAllocationsByHash.hasKey(returnAddressHash):
      var summary = self.stackAllocationsByHash[returnAddressHash]
      summary.totalAllocatedSize = max(0, summary.totalAllocatedSize + sizeDelta)
      summary.allocationCount = max(0, summary.allocationCount + allocationDelta)
      summary.totalAllocationCount = max(0, summary.totalAllocationCount + totalAllocationDelta)
      if summary.stackTrace.isNil and not stackTrace.isNil:
        summary.stackTrace = stackTrace

      self.stackAllocationsByHash[returnAddressHash] = summary
      return

    if sizeDelta <= 0 or allocationDelta <= 0:
      return

    self.stackAllocationsByHash[returnAddressHash] = StackAllocationSummary(
      returnAddressHash: returnAddressHash,
      stackTrace: stackTrace,
      totalAllocatedSize: sizeDelta,
      allocationCount: allocationDelta,
      totalAllocationCount: max(0, totalAllocationDelta),
    )

  proc appendStackHistorySample(summary: var StackAllocationSummary, sampleTime: float64) =
    summary.sizeHistory[summary.historyWriteCursor] = summary.totalAllocatedSize
    summary.countHistory[summary.historyWriteCursor] = summary.allocationCount
    summary.totalAllocationCountHistory[summary.historyWriteCursor] = summary.totalAllocationCount
    summary.sampleTimeHistory[summary.historyWriteCursor] = sampleTime
    summary.historyWriteCursor = (summary.historyWriteCursor + 1) mod stackHistoryEntries
    if summary.historyLen < stackHistoryEntries:
      inc summary.historyLen

  proc getStackHistoryOldestIndex(summary: StackAllocationSummary): int =
    if summary.historyLen <= 0:
      return 0
    if summary.historyLen < stackHistoryEntries:
      return 0
    return summary.historyWriteCursor

  proc getStackHistoryNewestIndex(summary: StackAllocationSummary): int =
    if summary.historyLen <= 0:
      return 0
    return (summary.historyWriteCursor - 1 + stackHistoryEntries) mod stackHistoryEntries

  proc updateStackAllocationHistory(self: ProfilerView) =
    let sampleTime = currentTimeSeconds()
    for _, summary in mpairs(self.stackAllocationsByHash):
      summary.appendStackHistorySample(sampleTime)
      if summary.historyLen >= 2:
        let oldestIndex = summary.getStackHistoryOldestIndex()
        let newestIndex = summary.getStackHistoryNewestIndex()
        let elapsedSeconds = summary.sampleTimeHistory[newestIndex] - summary.sampleTimeHistory[oldestIndex]
        if elapsedSeconds > 0:
          let allocationDelta = max(0, summary.totalAllocationCountHistory[newestIndex] - summary.totalAllocationCountHistory[oldestIndex])
          summary.allocationsPerSecond = allocationDelta.float / elapsedSeconds
        else:
          summary.allocationsPerSecond = 0
      else:
        summary.allocationsPerSecond = 0

  proc getStackOldestSize(summary: StackAllocationSummary): int =
    if summary.historyLen <= 0:
      return summary.totalAllocatedSize

    let oldestIndex =
      if summary.historyLen < stackHistoryEntries:
        0
      else:
        summary.historyWriteCursor
    return summary.sizeHistory[oldestIndex]

  proc getStackNewestSize(summary: StackAllocationSummary): int =
    if summary.historyLen <= 0:
      return summary.totalAllocatedSize

    let newestIndex = (summary.historyWriteCursor - 1 + stackHistoryEntries) mod stackHistoryEntries
    return summary.sizeHistory[newestIndex]

  proc addPotentialLeakCandidate(self: ProfilerView, ptrValue: uint64) =
    if ptrValue == 0 or self.potentialLeakCandidateIndices.hasKey(ptrValue):
      return

    let idx = self.potentialLeakCandidates.len
    self.potentialLeakCandidates.add(ptrValue)
    self.potentialLeakCandidateIndices[ptrValue] = idx

  proc removePotentialLeakCandidate(self: ProfilerView, ptrValue: uint64) =
    if ptrValue == 0 or not self.potentialLeakCandidateIndices.hasKey(ptrValue):
      return

    let idx = self.potentialLeakCandidateIndices[ptrValue]
    let lastIdx = self.potentialLeakCandidates.len - 1
    let lastPtr = self.potentialLeakCandidates[lastIdx]

    self.potentialLeakCandidates[idx] = lastPtr
    self.potentialLeakCandidates.setLen(lastIdx)
    self.potentialLeakCandidateIndices[lastPtr] = idx
    self.potentialLeakCandidateIndices.del(ptrValue)

    if self.potentialLeakCandidates.len == 0:
      self.potentialLeakScanCursor = 0
    elif self.potentialLeakScanCursor > idx:
      dec self.potentialLeakScanCursor
      if self.potentialLeakScanCursor >= self.potentialLeakCandidates.len:
        self.potentialLeakScanCursor = 0

  proc tagSetToMask(tags: set[DaTag]): uint64 =
    result = 0'u64
    for tag in tags:
      result = result or (1'u64 shl ord(tag))

  proc isProfilerAllocation(tagMask: uint64): bool =
    ((tagMask shr ord(daProfiler)) and 1'u64) == 1'u64

  proc includeInStackChart(tagMask: uint64): bool =
    ((tagMask shr ord(daProfiler)) and 1'u64) == 0'u64

  proc processAllocatorEvent(self: ProfilerView, event: DaMetaEvent) =
    let visibleTagMask = tagSetToMask(self.leakVisibleTags)
    if isProfilerAllocation(event.tag):
      return

    case event.kind
    of dmekAlloc, dmekAlloc0:
      if event.newPtr == 0 or event.newUsableSize <= 0:
        return

      if self.allocationsByPtr.hasKey(event.newPtr):
        let existing = self.allocationsByPtr[event.newPtr]
        self.applyAllocationDelta(existing.tagMask, -existing.usableSize)
        if includeInStackChart(existing.tagMask):
          self.applyStackAllocationDelta(existing.returnAddressHash, existing.stackTrace, -existing.usableSize, -1)
        # self.removePotentialLeakCandidate(event.newPtr)

      let tracked = TrackedAllocation(
        tagMask: event.tag,
        usableSize: event.newUsableSize,
        allocTimestamp: event.timestamp,
        threadId: event.threadId,
        returnAddressHash: event.returnAddressHash,
        stackTrace: event.stackTrace,
      )
      self.allocationsByPtr[event.newPtr] = tracked
      self.applyAllocationDelta(tracked.tagMask, tracked.usableSize)
      if includeInStackChart(tracked.tagMask):
        self.applyStackAllocationDelta(tracked.returnAddressHash, tracked.stackTrace, tracked.usableSize, 1, totalAllocationDelta = 1)
      # if tracked.usableSize >= leakMinTrackedSize and (event.tag and visibleTagMask) != 0:
      #   self.addPotentialLeakCandidate(event.newPtr)

    of dmekFree:
      if event.oldPtr == 0:
        return

      if self.allocationsByPtr.hasKey(event.oldPtr):
        let tracked = self.allocationsByPtr[event.oldPtr]
        self.applyAllocationDelta(tracked.tagMask, -tracked.usableSize)
        if includeInStackChart(tracked.tagMask):
          self.applyStackAllocationDelta(tracked.returnAddressHash, tracked.stackTrace, -tracked.usableSize, -1)
        self.allocationsByPtr.del(event.oldPtr)
        # self.removePotentialLeakCandidate(event.oldPtr)
      elif event.oldUsableSize > 0:
        self.applyAllocationDelta(event.tag, -event.oldUsableSize)

    of dmekRealloc:
      if event.newPtr == 0:
        return

      if event.oldPtr != 0 and self.allocationsByPtr.hasKey(event.oldPtr):
        let previous = self.allocationsByPtr[event.oldPtr]
        self.applyAllocationDelta(previous.tagMask, -previous.usableSize)
        if includeInStackChart(previous.tagMask):
          self.applyStackAllocationDelta(previous.returnAddressHash, previous.stackTrace, -previous.usableSize, -1)
        self.allocationsByPtr.del(event.oldPtr)
        # self.removePotentialLeakCandidate(event.oldPtr)
      elif event.oldPtr != 0 and event.oldUsableSize > 0:
        self.applyAllocationDelta(event.tag, -event.oldUsableSize)

      if event.newUsableSize <= 0:
        return

      if self.allocationsByPtr.hasKey(event.newPtr):
        let existing = self.allocationsByPtr[event.newPtr]
        self.applyAllocationDelta(existing.tagMask, -existing.usableSize)
        if includeInStackChart(existing.tagMask):
          self.applyStackAllocationDelta(existing.returnAddressHash, existing.stackTrace, -existing.usableSize, -1)
        # self.removePotentialLeakCandidate(event.newPtr)

      let tracked = TrackedAllocation(
        tagMask: event.tag,
        usableSize: event.newUsableSize,
        allocTimestamp: event.timestamp,
        threadId: event.threadId,
        returnAddressHash: event.returnAddressHash,
        stackTrace: event.stackTrace,
      )
      self.allocationsByPtr[event.newPtr] = tracked
      self.applyAllocationDelta(tracked.tagMask, tracked.usableSize)
      if includeInStackChart(tracked.tagMask):
        self.applyStackAllocationDelta(tracked.returnAddressHash, tracked.stackTrace, tracked.usableSize, 1, totalAllocationDelta = 1)
      # if tracked.usableSize >= leakMinTrackedSize and (event.tag and visibleTagMask) != 0:
      #   self.addPotentialLeakCandidate(event.newPtr)

  proc computePotentialLeaks(self: ProfilerView, now: float64, minAgeSeconds: float64, maxResults: int, maxScanPerTick: int) =
    let startedAt = currentTimeSeconds()
    defer:
      let elapsedMs = (currentTimeSeconds() - startedAt) * 1000.0

    if maxResults <= 0 or maxScanPerTick <= 0:
      self.cachedPotentialLeaks.setLen(0)
      self.potentialLeakCycleResults.setLen(0)
      self.potentialLeakScanCursor = 0
      return

    let candidateCount = self.potentialLeakCandidates.len
    if candidateCount == 0:
      self.cachedPotentialLeaks.setLen(0)
      self.potentialLeakCycleResults.setLen(0)
      self.potentialLeakScanCursor = 0
      return

    let startCursor = self.potentialLeakScanCursor mod candidateCount
    let batchSize = min(candidateCount, maxScanPerTick)
    let completedFullPass = startCursor + batchSize >= candidateCount
    let visibleTagMask = tagSetToMask(self.leakVisibleTags)

    for i in 0..<batchSize:
      let idx = (startCursor + i) mod candidateCount
      let ptrValue = self.potentialLeakCandidates[idx]
      if not self.allocationsByPtr.hasKey(ptrValue):
        continue

      let tracked = self.allocationsByPtr[ptrValue]
      if tracked.usableSize <= 0:
        continue
      if (tracked.tagMask and visibleTagMask) == 0'u64:
        continue

      let ageSeconds = max(0.0, now - tracked.allocTimestamp)
      if ageSeconds < minAgeSeconds:
        continue

      let score = ageSeconds * tracked.usableSize.float
      self.potentialLeakCycleResults.add PotentialLeak(
        ptrValue: ptrValue,
        tagMask: tracked.tagMask,
        usableSize: tracked.usableSize,
        ageSeconds: ageSeconds,
        threadId: tracked.threadId,
        returnAddressHash: tracked.returnAddressHash,
        stackTrace: tracked.stackTrace,
        score: score,
      )

    self.potentialLeakScanCursor = (startCursor + batchSize) mod candidateCount
    if completedFullPass:
      self.potentialLeakCycleResults.sort(proc(a, b: PotentialLeak): int = cmp(b.score, a.score))
      if self.potentialLeakCycleResults.len > maxResults:
        self.potentialLeakCycleResults.setLen(maxResults)
      self.cachedPotentialLeaks = self.potentialLeakCycleResults
      self.potentialLeakCycleResults.setLen(0)

  proc formatLeakStackTrace(trace: cstring, maxLen: int = 2000): string =
    if trace.isNil:
      return "<no stack trace>"

    result = $trace
    return
    result = result.replace("\r\n", " || ").replace("\n", " || ").replace("\r", " || ").replace(" || at ", " at ")

    # let filterMarkers = ["debug_allocator.nim", "LoadLibraryExA", "NimMain"]
    # for filterMarker in filterMarkers:
    #   let markerPos = result.rfind(filterMarker)
    #   if markerPos >= 0:
    #     let separatorPos = result.find("||", markerPos)
    #     if separatorPos >= 0 and separatorPos + 1 < result.len:
    #       result = result[(separatorPos + 1)..^1].strip()
    #     elif markerPos + filterMarker.len < result.len:
    #       result = result[(markerPos + filterMarker.len)..^1].strip()
    #     else:
    #       result = ""

    var filteredFrames: seq[string] = @[]
    for frame in result.split(" || "):
      let trimmedFrame = frame.strip()
      if trimmedFrame.len == 0 or trimmedFrame.contains("<unknown>"):
        continue
      filteredFrames.add(trimmedFrame)
    result = filteredFrames.join("\n")

    if result.len == 0:
      result = "<no caller frames>"

    if result.len > maxLen:
      result = result[0..<maxLen] & "..."

  proc formatVisibleLeakTags(self: ProfilerView): string =
    if self.leakVisibleTags.card == 0:
      return "<none>"

    var names: seq[string] = @[]
    for tag in self.leakVisibleTags:
      names.add($tag)
    names.sort(system.cmp[string])
    return names.join(", ")

  proc processAllocatorEvents(self: ProfilerView): int =
    let oldest = daGetMetaOldestIndex()
    let write = daGetMetaWriteIndex()
    if self.allocatorEventReadIndex < oldest:
      self.allocatorEventReadIndex = oldest

    const maxTries = 5
    var tries = maxTries
    var event: DaMetaEvent
    while self.allocatorEventReadIndex < write:
      if not daReadMetaEvent(self.allocatorEventReadIndex, event):
        let newOldest = daGetMetaOldestIndex()
        if self.allocatorEventReadIndex < newOldest:
          self.allocatorEventReadIndex = newOldest
          continue
        if tries == 0:
          if event.sequence != 0:
            # got partial event
            if event.gen.load() mod 2 == 1 and event.sequence == event.sequence2 and event.sequence * 2 + 1 == event.gen.load():
              echo "got partial event which looks complete, process anyways (fingers crossed)"
              tries = maxTries
              self.processAllocatorEvent(event)
              inc self.allocatorEventReadIndex
              inc result
              continue

          inc self.allocatorEventReadIndex
          continue

        dec tries
        sleep(1)
        continue

      tries = maxTries

      self.processAllocatorEvent(event)
      inc self.allocatorEventReadIndex
      inc result

  proc getProfiler(): ProfilerView =
    if gProfiler == nil:
      gProfiler = ProfilerView()
      gProfiler.eventHandlers = initTable[string, EventHandler](initialEventHandlersCapacity)
      gProfiler.allocationsByPtr = initTable[uint64, TrackedAllocation](initialAllocationsCapacity)
      gProfiler.potentialLeakCandidates = newSeqOfCap[uint64](initialLeakCandidateCapacity)
      gProfiler.potentialLeakCandidateIndices = initTable[uint64, int](initialLeakCandidateCapacity)
      gProfiler.potentialLeakCycleResults = newSeqOfCap[PotentialLeak](initialLeakResultsCapacity)
      gProfiler.cachedPotentialLeaks = newSeqOfCap[PotentialLeak](initialLeakResultsCapacity)
      gProfiler.stackAllocationsByHash = initTable[uint64, StackAllocationSummary](initialStackAllocationsCapacity)
      gProfiler.snapshotAggregatedValues = newSeqOfCap[int](initialSnapshotAggregateCapacity)
      gProfiler.stackScratch = newSeqOfCap[StackAllocationSummary](initialStackAllocationsCapacity)
      gProfiler.sortedTagBitsScratch = newSeqOfCap[int](initialTagSortScratchCapacity)
      gProfiler.renderCommandPool = newSeqOfCap[ref RenderCommands](initialRenderCommandPoolCapacity)
      gProfiler.leakVisibleTags = {daTextEditorCommand}
      gProfiler.allocatorEventReadIndex = daGetMetaOldestIndex()
    return gProfiler

  proc profProcessAllocatorEvents() {.modrtl.} =
    daTag(daProfiler)
    let p = getProfiler()
    p.allocatorEventsSinceLastSnapshot += p.processAllocatorEvents()

  proc textPanel(builder: UINodeBuilder, text: string, textColor: Color, fontScale: float = 1) =
    builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = text, textColor = textColor, fontScale = fontScale)

  proc button(builder: UINodeBuilder, text: string, textColor: Color, backgroundColor: Color, handler: proc() {.gcsafe, raises: [].}) =
    builder.panel(&{SizeToContentX, SizeToContentY, DrawText, FillBackground, MouseHover, DrawBorder}, text = text, textColor = textColor, backgroundColor = backgroundColor, border = textColor, border = border(1)):
      onClickAny btn:
        handler()

  proc formatMemoryMulti(value: int): string =
    let clamped = max(0, value)
    let kb = clamped.float / 1024.0
    let mb = clamped.float / (1024.0 * 1024.0)
    let gb = clamped.float / (1024.0 * 1024.0 * 1024.0)
    return fmt"{clamped} B | {kb:.2f} KB | {mb:.2f} MB | {gb:.2f} GB"

  proc formatSignedMemoryMulti(value: int): string =
    let sign = if value >= 0: "+" else: "-"
    let absValue = abs(value)
    let kb = absValue.float / 1024.0
    let mb = absValue.float / (1024.0 * 1024.0)
    let gb = absValue.float / (1024.0 * 1024.0 * 1024.0)
    return fmt"{sign}{absValue} B | {sign}{kb:.2f} KB | {sign}{mb:.2f} MB | {sign}{gb:.2f} GB"

  proc stackSortModeLabel(mode: StackSortMode): string =
    case mode
    of ssmTotalSize:
      return "Total Size"
    of ssmAllocationCount:
      return "Allocation Count"
    of ssmTotalAllocations:
      return "Total Allocations"
    of ssmAllocationsPerSecond:
      return "Allocations/s"

  proc stackMetricValue(summary: StackAllocationSummary, mode: StackSortMode): float64 =
    case mode
    of ssmTotalSize:
      return max(0, summary.totalAllocatedSize).float
    of ssmAllocationCount:
      return max(0, summary.allocationCount).float
    of ssmTotalAllocations:
      return max(0, summary.totalAllocationCount).float
    of ssmAllocationsPerSecond:
      return max(0.0, summary.allocationsPerSecond)

  proc stackBaselineMetricValue(summary: StackAllocationSummary, mode: StackSortMode): float64 =
    case mode
    of ssmTotalSize:
      return max(0, summary.baselineSize).float
    of ssmAllocationCount:
      return max(0, summary.baselineCount).float
    of ssmTotalAllocations:
      return max(0, summary.baselineTotalAllocationCount).float
    of ssmAllocationsPerSecond:
      return max(0.0, summary.baselineAllocationsPerSecond)

  proc stackMetricThreshold(mode: StackSortMode): float64 =
    case mode
    of ssmTotalSize:
      return stackChartMinTotalSize.float
    of ssmAllocationCount:
      return stackChartMinAllocationCount.float
    of ssmTotalAllocations:
      return stackChartMinTotalAllocationCount.float
    of ssmAllocationsPerSecond:
      return stackChartMinAllocationsPerSecond

  proc stackMetricThresholdLabel(mode: StackSortMode): string =
    case mode
    of ssmTotalSize:
      return fmt">= {stackChartMinTotalSize div 1024}KB"
    of ssmAllocationCount:
      return fmt">= {stackChartMinAllocationCount} allocs"
    of ssmTotalAllocations:
      return fmt">= {stackChartMinTotalAllocationCount} total allocs"
    of ssmAllocationsPerSecond:
      return fmt">= {stackChartMinAllocationsPerSecond:.1f}/s"

  proc formatStackMetricValue(value: float64, mode: StackSortMode): string =
    case mode
    of ssmTotalSize:
      return formatMemoryMulti(int(max(0.0, value)))
    of ssmAllocationCount:
      return $max(0, int(value))
    of ssmTotalAllocations:
      return $max(0, int(value))
    of ssmAllocationsPerSecond:
      return fmt"{max(0.0, value):.2f}/s"

  proc nextStackSortMode(mode: StackSortMode): StackSortMode =
    case mode
    of ssmTotalSize:
      return ssmAllocationCount
    of ssmAllocationCount:
      return ssmTotalAllocations
    of ssmTotalAllocations:
      return ssmAllocationsPerSecond
    of ssmAllocationsPerSecond:
      return ssmTotalSize

  proc passesStackMetricThreshold(summary: StackAllocationSummary, mode: StackSortMode): bool =
    stackMetricValue(summary, mode) >= stackMetricThreshold(mode)

  proc sortStacksByMetric(stacks: var seq[StackAllocationSummary], mode: StackSortMode) =
    stacks.sort(proc(a, b: StackAllocationSummary): int =
      let metricCmp = cmp(stackMetricValue(b, mode), stackMetricValue(a, mode))
      if metricCmp != 0:
        return metricCmp
      return cmp(b.totalAllocatedSize, a.totalAllocatedSize)
    )

  proc acquireRenderCommandBuffer(self: ProfilerView): ref RenderCommands =
    if self.renderCommandPoolCursor >= self.renderCommandPool.len:
      var commands: ref RenderCommands
      new(commands)
      self.renderCommandPool.add(commands)

    result = self.renderCommandPool[self.renderCommandPoolCursor]
    result[].clear()
    inc self.renderCommandPoolCursor

  proc sortedTagBitsByAllocationSize(self: ProfilerView): seq[int] =
    self.sortedTagBitsScratch.setLen(0)
    for tag in low(DaTag)..high(DaTag):
      self.sortedTagBitsScratch.add(ord(tag))

    self.sortedTagBitsScratch.sort(proc(a, b: int): int =
      let sizeCmp = cmp(self.tagAllocatedSizes[b], self.tagAllocatedSizes[a])
      if sizeCmp != 0:
        return sizeCmp
      return cmp(a, b)
    )
    return self.sortedTagBitsScratch

  proc getProfilerStaticBytes(): int =
    # Static profiler footprint is the fixed-size storage baked into one ProfilerView instance.
    sizeof(array[maxProfilerSnapshots, MemorySnapshot])

  proc writeSnapshotDumpToFile(self: ProfilerView) {.gcsafe, raises: [].} =
    try:
      let dumpTimestamp = now().format("yyyy-MM-dd-HH-mm-ss")
      let dumpPath = "logs/profiler-dump-" & dumpTimestamp & ".txt"
      createDir("logs")

      let latestSnapshot =
        if self.snapshotLen > 0:
          self.snapshotAt(self.snapshotLen - 1)
        else:
          MemorySnapshot()

      var lines = newSeqOfCap[string](256 + self.stackAllocationsByHash.len * 10)
      lines.add("Nev Profiler Dump")
      lines.add("Generated: " & now().format("yyyy-MM-dd HH:mm:ss"))
      lines.add("Baseline captured: " & (if self.baselineReferenceCaptured: "yes" else: "no"))
      lines.add("")
      lines.add("Summary")
      let totalCurrent = max(0, latestSnapshot.globalAllocatedBytes)
      let totalBaseline = max(0, self.baselineSeriesValue(sskTotal, -1, totalCurrent))
      let untaggedCurrent = max(0, latestSnapshot.untaggedAllocatedBytes)
      let untaggedBaseline = max(0, self.baselineSeriesValue(sskUntagged, -1, untaggedCurrent))
      lines.add(fmt"  Total    | Current: {formatMemoryMulti(totalCurrent)} | Baseline: {formatMemoryMulti(totalBaseline)} | Delta: {formatSignedMemoryMulti(totalCurrent - totalBaseline)}")
      lines.add(fmt"  Untagged | Current: {formatMemoryMulti(untaggedCurrent)} | Baseline: {formatMemoryMulti(untaggedBaseline)} | Delta: {formatSignedMemoryMulti(untaggedCurrent - untaggedBaseline)}")
      lines.add("")

      lines.add("Tags (sorted by current allocation size)")
      for bit in self.sortedTagBitsByAllocationSize():
        let tagName =
          if bit in ord(low(DaTag))..ord(high(DaTag)):
            $DaTag(bit)
          else:
            fmt"Tag[{bit}]"
        let currentValue = max(0, latestSnapshot.tagAllocatedBytes[bit])
        let baselineValue = max(0, self.baselineSeriesValue(sskTag, bit, currentValue))
        let deltaValue = currentValue - baselineValue
        lines.add(fmt"  {tagName:<20} | Current: {formatMemoryMulti(currentValue)} | Baseline: {formatMemoryMulti(baselineValue)} | Delta: {formatSignedMemoryMulti(deltaValue)}")
      lines.add("")

      var stacks = newSeqOfCap[StackAllocationSummary](self.stackAllocationsByHash.len)
      for _, summary in self.stackAllocationsByHash:
        stacks.add(summary)
      stacks.sort(proc(a, b: StackAllocationSummary): int = cmp(b.totalAllocatedSize, a.totalAllocatedSize))

      lines.add(fmt"Stack Traces ({stacks.len})")
      if stacks.len == 0:
        lines.add("  <none>")
      else:
        for i, stackSummary in stacks:
          let currentSize = max(0, stackSummary.totalAllocatedSize)
          let baselineSize = max(0, stackSummary.baselineSize)
          lines.add("")
          lines.add(fmt"  [{i + 1}] Hash: 0x{stackSummary.returnAddressHash.toHex}")
          lines.add(fmt"      Allocations: {stackSummary.allocationCount}")
          lines.add(fmt"      Current: {formatMemoryMulti(currentSize)}")
          lines.add(fmt"      Baseline: {formatMemoryMulti(baselineSize)}")
          lines.add(fmt"      Delta: {formatSignedMemoryMulti(currentSize - baselineSize)}")
          lines.add("      Stack Trace:")
          let traceText = formatLeakStackTrace(stackSummary.stackTrace, maxLen = int.high)
          for traceLine in traceText.splitLines():
            lines.add("        " & traceLine)

      writeFile(dumpPath, lines.join("\n"))
    except CatchableError:
      discard

  proc renderSnapshotChart(self: ProfilerView, builder: UINodeBuilder, barUpColor: Color, barDownColor: Color, chartBackgroundColor: Color, seriesKind: SnapshotSeriesKind, viewportTop: float, viewportBottom: float, tagBit: int = -1, chartHeight: float = 100) =
    builder.panel(&{FillX, SizeToContentY, LayoutVertical}):
      let currentSeriesValue =
        if self.snapshotLen > 0:
          max(0, snapshotSeriesValue(self.snapshotAt(self.snapshotLen - 1), seriesKind, tagBit))
        else:
          0
      let baselineValue = self.baselineSeriesValue(seriesKind, tagBit, currentSeriesValue)
      let deltaValue = currentSeriesValue - baselineValue
      let headerText = fmt"{seriesLabel(seriesKind, tagBit)}: {formatMemoryMulti(currentSeriesValue)} | Delta {formatSignedMemoryMulti(deltaValue)}"
      textPanel(builder, headerText, barUpColor, fontScale = 0.9)
      builder.panel(&{FillX, SizeToContentY, FillBackground, MouseHover}, h = chartHeight, backgroundColor = chartBackgroundColor, tag = "profiler-chart"):
        let boundsAbsolute = currentNode.boundsAbsolute
        let chartTop = boundsAbsolute.y
        let chartBottom = boundsAbsolute.y + boundsAbsolute.h
        if chartBottom <= viewportTop or chartTop >= viewportBottom:
          currentNode.renderCommands.clear()
          currentNode.renderCommandList.setLen(0)
          return

        let bounds = currentNode.bounds
        currentNode.renderCommands.clear()
        currentNode.renderCommandList.setLen(0)

        if self.snapshotLen <= 0:
          return

        let chartCommands = self.acquireRenderCommandBuffer()
        currentNode.renderCommandList.add(chartCommands)

        let maxBars = max(1, int(bounds.w * 0.5))
        let displayedBars = min(self.snapshotLen, maxBars)
        let logicalSamplesPerBar = self.snapshotLen.float / displayedBars.float
        self.snapshotAggregatedValues.setLen(displayedBars)
        for i in 0..<displayedBars:
          let rangeStart = i.float * logicalSamplesPerBar
          let rangeEnd = (i + 1).float * logicalSamplesPerBar
          self.snapshotAggregatedValues[i] = self.averagedSnapshotSeriesValue(seriesKind, tagBit, rangeStart, rangeEnd)

        var minAllocatedBytesVisible = int.high
        var maxAllocatedBytes = int.low
        for i in 0..<displayedBars:
          let value = self.snapshotAggregatedValues[i]
          minAllocatedBytesVisible = min(minAllocatedBytesVisible, value)
          maxAllocatedBytes = max(maxAllocatedBytes, value)

        let nthOffset = max(0, self.baselineSnapshotN - 1)
        let desiredBaselineLogicalIndex = nthOffset
        let baselineLogicalIndex =
          if desiredBaselineLogicalIndex in 0..<self.snapshotLen:
            desiredBaselineLogicalIndex
          elif desiredBaselineLogicalIndex - 1 in 0..<self.snapshotLen:
            desiredBaselineLogicalIndex - 1
          else:
            max(0, self.snapshotLen - 1)
        let dynamicBaseline = max(0, snapshotSeriesValue(self.snapshotAt(baselineLogicalIndex), seriesKind, tagBit))
        let minAllocatedBytes = max(0, self.baselineSeriesValue(seriesKind, tagBit, dynamicBaseline))
        let maxAboveThreshold = max(0, maxAllocatedBytes - minAllocatedBytes)
        let maxBelowThreshold = max(0, minAllocatedBytes - minAllocatedBytesVisible)

        let barWidth = max(1.0, bounds.w / displayedBars.float)

        onHover:
          let hoveredDisplayedIndex = clamp(int(floor(pos.x / barWidth)), 0, displayedBars - 1)
          let hoveredRangeStart = hoveredDisplayedIndex.float * logicalSamplesPerBar
          let hoveredRangeEnd = (hoveredDisplayedIndex + 1).float * logicalSamplesPerBar
          let hoveredLogicalIndex = clamp(int((hoveredRangeStart + hoveredRangeEnd) * 0.5), 0, self.snapshotLen - 1)
          if hoveredLogicalIndex != self.hoveredSnapshotLogicalIndex or self.hoveredSeriesKind != seriesKind or self.hoveredSeriesTagBit != tagBit:
            self.hoveredSnapshotLogicalIndex = hoveredLogicalIndex
            self.hoveredSeriesKind = seriesKind
            self.hoveredSeriesTagBit = tagBit
            self.markDirty()

        onEndHover:
          if self.hoveredSnapshotLogicalIndex >= 0:
            self.hoveredSnapshotLogicalIndex = -1
            self.markDirty()

        buildCommands(chartCommands[]):
          let centerY = bounds.h * 0.5
          for i in 0..<displayedBars:
            let bytes = self.snapshotAggregatedValues[i]
            let delta = bytes - minAllocatedBytes
            let x = i.float * barWidth
            if delta >= 0:
              let ratio = min(1.0, max(0.0, abs(delta).float / maxAboveThreshold.float))
              let barHeight = max(1.0, centerY * ratio)
              let y = centerY - barHeight
              let barColor = barUpColor
              fillRect(rect(x, y, barWidth, barHeight), barColor)
            else:
              let ratio = min(1.0, max(0.0, abs(delta).float / maxBelowThreshold.float))
              let barHeight = max(1.0, centerY * ratio)
              let y = centerY
              let barColor = barDownColor
              fillRect(rect(x, y, barWidth, barHeight), barColor)

  proc renderStackAllocationChart(self: ProfilerView, builder: UINodeBuilder, chartBackgroundColor: Color, textColor: Color, increasingColor: Color, decreasingColor: Color, viewportTop: float, viewportBottom: float, chartHeight: float = 140) =
    let sortMode = self.stackSortMode
    builder.panel(&{FillX, SizeToContentY, LayoutVertical}):
      self.stackScratch.setLen(0)
      var hiddenTotalSize = 0
      var hiddenTotalCount = 0
      for _, summary in self.stackAllocationsByHash:
        if passesStackMetricThreshold(summary, sortMode):
          self.stackScratch.add(summary)
        else:
          hiddenTotalSize += max(0, summary.totalAllocatedSize)
          hiddenTotalCount += max(0, summary.allocationCount)

      textPanel(builder, &"Total Unique Stacks: {self.stackScratch.len} ({stackSortModeLabel(sortMode)} {stackMetricThresholdLabel(sortMode)})", textColor)
      textPanel(builder, &"Stacks ({self.stackScratch.len}) | Sorted by {stackSortModeLabel(sortMode)}", textColor)

      button(builder, " Stack Sort: " & stackSortModeLabel(self.stackSortMode) & " ", textColor, chartBackgroundColor.lighten(0.2), proc() {.gcsafe, raises: [].} =
        self.stackSortMode = nextStackSortMode(self.stackSortMode)
        self.markDirty()
      )

      sortStacksByMetric(self.stackScratch, sortMode)

      builder.panel(&{FillX, SizeToContentY, FillBackground, MouseHover}, h = chartHeight, backgroundColor = chartBackgroundColor, tag = "profiler-stack-chart"):
        let boundsAbsolute = currentNode.boundsAbsolute
        let chartTop = boundsAbsolute.y
        let chartBottom = boundsAbsolute.y + boundsAbsolute.h
        if chartBottom <= viewportTop or chartTop >= viewportBottom:
          currentNode.renderCommands.clear()
          currentNode.renderCommandList.setLen(0)
          return

        let bounds = currentNode.bounds
        currentNode.renderCommands.clear()
        currentNode.renderCommandList.setLen(0)

        if self.stackScratch.len == 0 or bounds.w <= 0:
          return

        let chartCommands = self.acquireRenderCommandBuffer()
        currentNode.renderCommandList.add(chartCommands)

        var maxMetric = 1.0
        for stackSummary in self.stackScratch:
          maxMetric = max(maxMetric, max(stackBaselineMetricValue(stackSummary, sortMode), stackMetricValue(stackSummary, sortMode)))
        let barWidth = bounds.w / self.stackScratch.len.float

        onHover:
          let hoveredDisplayedIndex = clamp(int(floor(pos.x / barWidth)), 0, self.stackScratch.high)
          let hoveredHash = self.stackScratch[hoveredDisplayedIndex].returnAddressHash
          if hoveredHash != self.hoveredStackReturnAddressHash:
            self.hoveredStackReturnAddressHash = hoveredHash
            self.markDirty()

        onClickAny btn:
          if btn == MouseButton.Middle:
            let clickedDisplayedIndex = clamp(int(floor(pos.x / barWidth)), 0, self.stackScratch.high)
            let clickedHash = self.stackScratch[clickedDisplayedIndex].returnAddressHash
            daSetBreakOnReturnAddressHash(clickedHash)
            if clickedHash != self.hoveredStackReturnAddressHash:
              self.hoveredStackReturnAddressHash = clickedHash
            self.markDirty()

        onEndHover:
          discard

        buildCommands(chartCommands[]):
          for i in 0..<self.stackScratch.len:
            let stackSummary = self.stackScratch[i]
            let x = i.float * barWidth
            let baselineMetric = stackBaselineMetricValue(stackSummary, sortMode)
            let currentMetric = stackMetricValue(stackSummary, sortMode)
            let baselineRatio = min(1.0, max(0.0, baselineMetric / maxMetric))
            let currentRatio = min(1.0, max(0.0, currentMetric / maxMetric))
            let baselineBarHeight = max(1.0, bounds.h * baselineRatio)
            let currentBarHeight = max(1.0, bounds.h * currentRatio)
            let baselineY = bounds.h - baselineBarHeight
            let currentY = bounds.h - currentBarHeight

            let trendColor =
              if currentMetric > baselineMetric:
                increasingColor
              elif currentMetric < baselineMetric:
                decreasingColor
              else:
                textColor

            let currentBarColor =
              if self.hoveredStackReturnAddressHash != 0 and stackSummary.returnAddressHash == self.hoveredStackReturnAddressHash:
                trendColor.lighten(0.2)
              else:
                trendColor
            let baselineBarColor = trendColor.darken(0.2).withAlpha(0.5)
            fillRect(rect(x, currentY, max(1.0, barWidth), currentBarHeight), currentBarColor)
            fillRect(rect(x, baselineY, max(1.0, barWidth), baselineBarHeight), baselineBarColor)

      var hoveredVisibleIndex = -1
      if self.hoveredStackReturnAddressHash != 0:
        for i, stackSummary in self.stackScratch:
          if stackSummary.returnAddressHash == self.hoveredStackReturnAddressHash:
            hoveredVisibleIndex = i
            break

      if hoveredVisibleIndex >= 0:
        let hoveredStack = self.stackScratch[hoveredVisibleIndex]
        let baselineMetric = stackBaselineMetricValue(hoveredStack, sortMode)
        let currentMetric = stackMetricValue(hoveredStack, sortMode)
        var biggerTotalSize = 0
        var biggerTotalCount = 0
        var smallerTotalSize = 0
        var smallerTotalCount = 0
        for stackSummary in self.stackScratch:
          if stackMetricValue(stackSummary, sortMode) > stackMetricValue(hoveredStack, sortMode):
            biggerTotalSize += max(0, stackSummary.totalAllocatedSize)
            biggerTotalCount += max(0, stackSummary.allocationCount)
          elif stackMetricValue(stackSummary, sortMode) < stackMetricValue(hoveredStack, sortMode):
            smallerTotalSize += max(0, stackSummary.totalAllocatedSize)
            smallerTotalCount += max(0, stackSummary.allocationCount)

        textPanel(builder, &"Hash:     0x{hoveredStack.returnAddressHash.toHex}", textColor, fontScale = 0.9)
        textPanel(builder, &"count:    {max(0, hoveredStack.allocationCount)}", textColor, fontScale = 0.9)
        textPanel(builder, &"size:     {formatMemoryMulti(max(0, hoveredStack.totalAllocatedSize))}", textColor, fontScale = 0.9)
        textPanel(builder, &"current:  {formatStackMetricValue(currentMetric, sortMode)}", textColor, fontScale = 0.9)
        textPanel(builder, &"baseline: {formatStackMetricValue(baselineMetric, sortMode)}", textColor, fontScale = 0.9)
        textPanel(builder, &"delta:    {formatStackMetricValue(currentMetric - baselineMetric, sortMode)}", textColor, fontScale = 0.9)
        textPanel(builder, &"> Hover:  {formatMemoryMulti(biggerTotalSize)} | allocs: {biggerTotalCount}", textColor, fontScale = 0.9)
        textPanel(builder, &"< Hover:  {formatMemoryMulti(smallerTotalSize)} | allocs: {smallerTotalCount}", textColor, fontScale = 0.9)
        textPanel(builder, &"Hidden:   {formatMemoryMulti(hiddenTotalSize)} | allocs: {hiddenTotalCount}", textColor, fontScale = 0.9)
        builder.panel(&{DrawText, TextMultiline, TextWrap, SizeToContentX, SizeToContentY},
          text = &"  {formatLeakStackTrace(hoveredStack.stackTrace)}", textColor = textColor, fontScale = 0.9)

  proc renderMemoryTab(self: ProfilerView, builder: UINodeBuilder,
      backgroundColor: Color, textColor: Color, numberColor: Color,
      chartColor: Color, chartDownColor: Color, chartBackgroundColor: Color,
      increasedColor: Color, decreasedColor: Color,
      viewportTop: float, viewportBottom: float) =
    let allocatedBytes = self.latestSnapshotBytes()
    let allocatedMb = allocatedBytes.float / (1024.0 * 1024.0)
    let allocatedGb = allocatedBytes.float / (1024.0 * 1024.0 * 1024.0)
    let allocatedKb = allocatedBytes.float / 1024.0
    let gbText = fmt"{allocatedGb:.2f}"
    let mbText = fmt"{allocatedMb:.2f}"
    let kbText = fmt"{allocatedKb:.2f}"
    let byteText = $allocatedBytes
    let stackTraceCacheBytes = max(0, daGetStackTraceCacheBytes())
    let debugAllocatorStaticBytes = max(0, daGetDebugAllocatorStaticBytes())
    let profilerStaticBytes = max(0, getProfilerStaticBytes())
    let profilerTaggedBytes =
      if ord(daProfiler) in 0..<64:
        max(0, self.tagAllocatedSizes[ord(daProfiler)])
      else:
        0

    builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
      button(builder, " Set Baseline ", textColor, backgroundColor.lighten(0.2), proc() {.gcsafe, raises: [].} =
        self.forceSetBaselineReference()
        self.markDirty()
      )
      button(builder, " Export Snapshot Dump ", textColor, backgroundColor.lighten(0.2), proc() {.gcsafe, raises: [].} =
        self.writeSnapshotDumpToFile()
      )

    builder.panel(&{SizeToContentX, SizeToContentY, LayoutVertical}):
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, $self.allocationsByPtr.len, numberColor)
        textPanel(builder, " allocations", textColor)
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, gbText, numberColor)
        textPanel(builder, " GB", textColor)
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, mbText, numberColor)
        textPanel(builder, " MB", textColor)
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, kbText, numberColor)
        textPanel(builder, " KB", textColor)
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, byteText, numberColor)
        textPanel(builder, " B", textColor)
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, formatMemoryMulti(stackTraceCacheBytes), numberColor)
        textPanel(builder, " allocator dynamic stack trace cache", textColor)
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, formatMemoryMulti(debugAllocatorStaticBytes), numberColor)
        textPanel(builder, " allocator static", textColor)
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, formatMemoryMulti(profilerTaggedBytes), numberColor)
        textPanel(builder, " profiler dynamic tagged", textColor)
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, formatMemoryMulti(profilerStaticBytes), numberColor)
        textPanel(builder, " profiler static", textColor)

    if self.hoveredSnapshotLogicalIndex in 0..<self.snapshotLen:
      let hoveredSnapshot = self.snapshotAt(self.hoveredSnapshotLogicalIndex)
      let hoveredValue = max(0, snapshotSeriesValue(hoveredSnapshot, self.hoveredSeriesKind, self.hoveredSeriesTagBit))
      let hoveredBaseline = max(0, self.baselineSeriesValue(self.hoveredSeriesKind, self.hoveredSeriesTagBit, hoveredValue))
      let hoveredDelta = hoveredValue - hoveredBaseline
      let hoveredKb = hoveredValue.float / 1024.0
      let hoveredMb = hoveredValue.float / (1024.0 * 1024.0)
      let hoveredGb = hoveredValue.float / (1024.0 * 1024.0 * 1024.0)
      let hoveredText = fmt"Hover {seriesLabel(self.hoveredSeriesKind, self.hoveredSeriesTagBit)}: {hoveredValue} B | {hoveredKb:.2f} KB | {hoveredMb:.2f} MB | {hoveredGb:.2f} GB | Delta {formatSignedMemoryMulti(hoveredDelta)}"
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, hoveredText, textColor)
    else:
      builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
        textPanel(builder, " ", textColor)

    self.renderSnapshotChart(builder, chartColor, chartDownColor, chartBackgroundColor, sskAllocatorEvents, viewportTop, viewportBottom, chartHeight = 50)
    self.renderSnapshotChart(builder, chartColor, chartDownColor, chartBackgroundColor, sskTotal, viewportTop, viewportBottom, chartHeight = 100)
    self.renderSnapshotChart(builder, chartColor, chartDownColor, chartBackgroundColor, sskUntagged, viewportTop, viewportBottom, chartHeight = 50)

    for bit in self.sortedTagBitsByAllocationSize():
      self.renderSnapshotChart(builder, chartColor, chartDownColor, chartBackgroundColor, sskTag, viewportTop, viewportBottom, tagBit = bit, chartHeight = 50)

    self.renderStackAllocationChart(builder, chartBackgroundColor, textColor, increasedColor, decreasedColor, viewportTop, viewportBottom)

  proc renderLeaksTab(self: ProfilerView, builder: UINodeBuilder,
      backgroundColor: Color, textColor: Color, leakLabelColor: Color) =
    let potentialLeaks = self.cachedPotentialLeaks
    builder.panel(&{SizeToContentX, SizeToContentY, LayoutVertical}):
      textPanel(builder, &"Potential Leaks ({potentialLeaks.len}/{self.potentialLeakCandidates.len}) | Tags: {self.formatVisibleLeakTags()}", leakLabelColor)

      if potentialLeaks.len == 0:
        textPanel(builder, &"No candidates older than {leakMinAgeSeconds:.0f}s", textColor)
      else:
        for i in 0..<potentialLeaks.len:
          let leak {.cursor.} = potentialLeaks[i]
          let leakHeader = &"#{i + 1} ptr=0x{leak.ptrValue.toHex} size={leak.usableSize} age={leak.ageSeconds:.1f}s tag=0x{leak.tagMask.toHex} tid={leak.threadId} hash=0x{leak.returnAddressHash.toHex}"
          let leakHeaderColor =
            if self.hoveredPotentialLeakPtr != 0 and leak.ptrValue == self.hoveredPotentialLeakPtr:
              textColor.lighten(0.2)
            else:
              textColor
          let ptrValue = leak.ptrValue
          builder.panel(&{DrawText, SizeToContentX, SizeToContentY, MouseHover, FillBackground}, text = leakHeader, textColor = leakHeaderColor, backgroundColor = backgroundColor):
            capture ptrValue:
              onHover:
                if self.hoveredPotentialLeakPtr != ptrValue:
                  self.hoveredPotentialLeakPtr = ptrValue
                  self.markDirty()

        if self.hoveredPotentialLeakPtr != 0:
          for i in 0..<potentialLeaks.len:
            let leak {.cursor.} = potentialLeaks[i]
            if leak.ptrValue == self.hoveredPotentialLeakPtr:
              builder.panel(&{DrawText, TextMultiline, TextWrap, SizeToContentX, SizeToContentY},
                text = &"  {formatLeakStackTrace(leak.stackTrace)}", textColor = textColor, fontScale = 0.9)

  proc renderProfiler*(self: ProfilerView, builder: UINodeBuilder) =
    daTag(daProfiler)
    self.renderCommandPoolCursor = 0
    let dirty = self.dirty
    self.resetDirty()

    let backgroundColor = if self.active: builder.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: builder.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(-0.025)
    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    let increasedColor = builder.theme.color("terminal.ansiBrightRed", color(120/255, 200/255, 120/255))
    let decreasedColor = builder.theme.color("terminal.ansiBrightGreen", color(220/255, 120/255, 120/255))
    let chartColor = builder.theme.color("terminal.ansiBrightRed", textColor.lighten(0.0))
    let chartDownColor = builder.theme.color("terminal.ansiBrightBlue", chartColor.darken(0.0))
    let chartBackgroundColor = builder.theme.color("editorWidget.background", backgroundColor.lighten(0.025))
    let leakLabelColor = builder.theme.color("terminal.ansiBrightYellow", textColor)
    let activeTabColor = builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255))
    let inactiveTabColor = builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
    let borderColor = builder.theme.color("panel.border", color(0, 0, 0))

    let allocatedBytes = self.latestSnapshotBytes()
    let previousAllocatedBytes = self.previousSnapshotBytes()
    let numberColor =
      if self.snapshotLen > 1 and allocatedBytes > previousAllocatedBytes: increasedColor
      elif self.snapshotLen > 1 and allocatedBytes < previousAllocatedBytes: decreasedColor
      else: textColor

    const tabLabels = ["Memory", "Leaks"]

    builder.panel(&{FillBackground, FillX, FillY, MaskContent, LayoutVertical}, backgroundColor = backgroundColor, tag = "profiler"):
      # Tab bar
      builder.panel(&{FillX, SizeToContentY, LayoutHorizontal, FillBackground}, backgroundColor = inactiveTabColor):
        for i in 0..<2:
          let tabBg = if self.activeTabIndex == i: activeTabColor else: inactiveTabColor
          capture i:
            button(builder, " " & tabLabels[i] & " ", textColor, tabBg, proc() {.gcsafe, raises: [].} =
              self.activeTabIndex = i
              self.tabScrollOffsets[i] = 0
              self.markDirty()
            )
      builder.panel(&{DrawBorder, DrawBorderTerminal, FillX}, h = 1, border = border(0, 0, 1, 0), borderColor = borderColor, backgroundColor = inactiveTabColor)

      # Scrollable content area
      builder.panel(&{FillX, FillY}):
        let viewportTop = currentNode.boundsAbsolute.y
        let viewportBottom = currentNode.boundsAbsolute.y + currentNode.boundsAbsolute.h
        onScroll:
          self.tabScrollOffsets[self.activeTabIndex] -= delta.y * builder.textHeight * 2
          self.markDirty()

        builder.panel(&{FillX, SizeToContentY, LayoutVertical}, tag = "scroll"):
          if self.activeTabIndex == 0:
            self.renderMemoryTab(builder, backgroundColor, textColor, numberColor, chartColor, chartDownColor, chartBackgroundColor, increasedColor, decreasedColor, viewportTop, viewportBottom)
          else:
            self.renderLeaksTab(builder, backgroundColor, textColor, leakLabelColor)

        self.tabScrollOffsets[self.activeTabIndex] = self.tabScrollOffsets[self.activeTabIndex].max(0)
        builder.currentChild.rawY = -self.tabScrollOffsets[self.activeTabIndex]

  proc getEventHandler(self: ProfilerView, context: string): EventHandler =
    let events = getServiceChecked(EventHandlerService)
    if context notin self.eventHandlers:
      var eventHandler: EventHandler
      assignEventHandler(eventHandler, events.getEventHandlerConfig(context)):
        onAction:
          if getServiceChecked(CommandService).executeCommand(action & " " & arg, false).isSome:
            Handled
          else:
            Ignored
        onInput:
          Ignored

      self.eventHandlers[context] = eventHandler
      return eventHandler

    return self.eventHandlers[context]

  proc getEventHandlers(self: ProfilerView, inject: Table[string, EventHandler]): seq[EventHandler] =
    daTag(daProfiler)
    result.add self.getEventHandler("profiler")

  proc init_module_profiler*() {.cdecl, exportc, dynlib.} =
    daTag(daProfiler)
    var view: ProfilerView = getProfiler()
    let allocatorEventsProcessed = view.processAllocatorEvents()
    view.addSnapshot(view.globalAllocatedSize, allocatorEventsProcessed)
    view.tryCaptureBaselineReference()

    view.renderImpl = proc(view: View, builder: UINodeBuilder): seq[OverlayFunction] {.closure, raises: [].} =
      renderProfiler(view.ProfilerView, builder)

    view.getEventHandlersImpl = proc(self: View, inject: Table[string, EventHandler]): seq[EventHandler] =
      getEventHandlers(self.ProfilerView, inject)

    view.kindImpl = proc(self: View): string = "Profiler"
    view.descImpl = proc(self: View): string = "Profiler"
    view.displayImpl = proc(self: View): string = "Profiler"
    view.copyImpl = proc(self: View): View = self

    let layout = getServiceChecked(LayoutService)
    let commands = getServiceChecked(CommandService)
    discard getServiceChecked(PlatformService).platform.onPreRender.subscribe proc(_: Platform) =
      withDaTag(daProfiler):
        view.allocatorEventsSinceLastSnapshot += view.processAllocatorEvents()
        let now = currentTimeSeconds()
        if now - view.lastSnapshotTimestamp >= snapshotInterval.float * 0.001:
          view.lastSnapshotTimestamp = now
          view.updateStackAllocationHistory()
          # view.computePotentialLeaks(now, minAgeSeconds = leakMinAgeSeconds, maxResults = leakMaxResults, maxScanPerTick = leakScanBatchPerTick)
          view.addSnapshot(view.globalAllocatedSize, allocatorEventsProcessed)
          view.tryCaptureBaselineReference()
          view.markDirty()
          view.allocatorEventsSinceLastSnapshot = 0

    layout.addViewFactory "Profiler", proc(config: JsonNode): View {.raises: [].} =
      return view

    template defineCommand(inName: string, desc: string, body: untyped): untyped =
      discard commands.registerCommand(command_service.Command(
        namespace: "",
        name: "profiler." & inName,
        description: desc,
        parameters: @[],
        returnType: "void",
        execute: proc(args {.inject.}: string): string {.gcsafe, raises: [].} =
          try:
            body
            return ""
          except CatchableError:
            return ""
      ))

    defineCommand("toggle", "Toggle Profiler UI"):
      if layout.isViewVisible(view):
        layout.closeView(view, keepHidden = false, restoreHidden = false)
      else:
        layout.addView(view, slot = "#small-left", focus = true)
        view.markDirty()
