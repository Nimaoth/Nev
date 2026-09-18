(
  (context selector)

  (inject (popup SelectorPopupImpl))

  (active-command setPreviewVisible [(visible bool)] () "")
  (active-command togglePreview [] () "")
  (active-command getSelectedItemJson [] JsonNode "")
  (active-command accept [] () "")
  (active-command sort [(sort ToggleBool)] () "")
  (active-command setMinScore [(value float) (add bool false)] () "")
  (active-command prev [(count int 1)] () "")
  (active-command next [(count int 1)] () "")
  (active-command selectNth [(n int)] () "")
  (active-command setFocusPreview [(focus bool)] () "")
  (active-command toggleFocusPreview [] () "")
)