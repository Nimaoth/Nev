(
  (context markdown)

  (map MarkdownComponent getMarkdownComponent)
  (inject (self MarkdownComponent))

  (active-command toggle-bold toggleBold [] (async) "")
  (active-command toggle-italic toggleItalic [] (async) "")
  (active-command toggle-code toggleCode [] (async) "")
  (active-command toggle-strikethrough toggleStrikethrough [] (async) "")
)