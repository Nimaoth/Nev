import std/[json, strutils, tables, options, macros, genasts]
import misc/[myjsonutils]

macro variant(name: untyped, types: varargs[untyped]): untyped =
  var variantType = quote do:
    type `name`* = object
      node: JsonNode

  var procs = nnkStmtList.newTree
  for t in types:
    # echo t.treeRepr
    var isSeq = false
    let typeName = if t.kind == nnkBracketExpr and t[0].strVal == "seq":
      # We got a seq of some type
      isSeq = true
      t[1].strVal & "Seq"
    else:
      t.strVal

    let isSeqLit = newLit(isSeq)

    let procName = ident("as" & typeName.capitalizeAscii)
    let ast = genAst(procName, name, t, isSeqLit):

      proc procName*(arg: name): Option[t] =
        try:
          when isSeqLit:
            if arg.node.kind != JArray:
              return t.none
          return arg.node.jsonTo(t, Joptions(allowMissingKeys: true, allowExtraKeys: false)).some
        except CatchableError:
          return t.none

      proc procName*(arg: Option[name]): Option[t] =
        if arg.isSome:
          return procName(arg.get)
        else:
          return t.none

    procs.add ast

  return quote do:
    `variantType`
    `procs`
    proc fromJsonHook*(a: var `name`, b: JsonNode, opt = Joptions()) =
      a.node = b

type
  PositionEncodingKind* {.pure.} = enum
    UTF8 = "utf-8"
    UTF16 = "utf-16"
    UTF32 = "utf-32"

  TextDocumentSyncKind* {.pure.} = enum
    None = 0
    Full = 1
    Incremental = 2

  CodeActionKind* {.pure.} = enum
    Empty = ""
    QuickFix = "quickfix"
    Refactor = "refactor"
    RefactorExtract = "refactor.extract"
    RefactorInline = "refactor.inline"
    RefactorRewrite = "refactor.rewrite"
    Source = "source"
    SourceOrganizeImports = "source.organizeImports"
    SourceFixAll = "source.fixAll"

  CompletionTriggerKind* {.pure.} = enum
    Invoked = 1
    TriggerCharacter = 2
    TriggerForIncompleteCompletions = 3

  FileOperationPatternKind* {.pure.} = enum
    File = "file"
    Folder = "folder"

  CompletionKind* {.pure.} = enum
    Text = 1
    Method = 2
    Function = 3
    Constructor = 4
    Field = 5
    Variable = 6
    Class = 7
    Interface = 8
    Module = 9
    Property = 10
    Unit = 11
    Value = 12
    Enum = 13
    Keyword = 14
    Snippet = 15
    Color = 16
    File = 17
    Reference = 18
    Folder = 19
    EnumMember = 20
    Constant = 21
    Struct = 22
    Event = 23
    Operator = 24
    TypeParameter = 25

  MessageType* {.pure.} = enum
    Error = 1
    Warning = 2
    Info = 3
    Log = 4

  CompletionItemTag* {.pure.} = enum
    Deprecated = 1

  MarkupKind* {.pure.} = enum
    PlainText = "plaintext"
    Markdown = "markdown"

  InsertTextFormat* {.pure.} = enum
    PlainText = 1
    Snippet = 2

  InsertTextMode* {.pure.} = enum
    AsIs = 1
    AdjustIndentation = 2

  ServerInfo* = object
    name*: string
    version*: string

  TextDocumentSyncOptionsSave* = object
    includeText*: Option[bool]

  TextDocumentSyncOptions* = object
    openClose*: bool
    change*: TextDocumentSyncKind
    willSave*: Option[bool]
    willSaveWaitUntil*: Option[bool]
    save*: Option[TextDocumentSyncOptionsSave]

  CompletionItemOptions* = object
    labelDetailsSupport*: bool

  CompletionOptions* = object
    workDoneProgress*: bool
    triggerCharacters*: seq[string]
    allCommitCharacters*: seq[string]
    resolveProvider*: bool
    completionItem*: Option[CompletionItemOptions]

  DocumentFilter* = object
    language*: Option[string]
    scheme*: Option[string]
    pattern*: Option[string]

  DocumentSelector* = seq[DocumentFilter]

  HoverOptions* = object
    workDoneProgress*: bool

  SignatureHelpOptions* = object
    workDoneProgress*: bool
    triggerCharacters*: seq[string]
    retriggerCharacters*: seq[string]

  DeclarationOptions* = object
    workDoneProgress*: bool

  DeclarationRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  DefinitionOptions* = object
    workDoneProgress*: bool

  TypeDefinitionOptions* = object
    workDoneProgress*: bool

  TypeDefinitionRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  ImplementationOptions* = object
    workDoneProgress*: bool

  ImplementationRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  ReferenceOptions* = object
    workDoneProgress*: bool

  DocumentHighlightOptions* = object
    workDoneProgress*: bool

  DocumentSymbolOptions* = object
    workDoneProgress*: bool

  CodeActionOptions* = object
    workDoneProgress*: bool
    codeActionKinds*: seq[CodeActionKind]
    resolveProvider*: bool

  CodeLensOptions* = object
    workDoneProgress*: bool
    resolveProvider*: bool

  DocumentLinkOptions* = object
    workDoneProgress*: bool
    resolveProvider*: bool

  DocumentOnTypeFormattingOptions* = object
    firstTriggerCharacter*: string
    moreTriggerCharacter*: seq[string]

  ExecuteCommandOptions = object
    workDoneProgress*: bool
    commands*: seq[string]

  DocumentColorOptions* = object
    workDoneProgress*: bool

  DocumentColorRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  DocumentFormattingOptions* = object
    workDoneProgress*: bool

  DocumentRangeFormattingOptions* = object
    workDoneProgress*: bool

  RenameOptions* = object
    workDoneProgress*: bool
    prepareProvider*: bool

  FoldingRangeOptions* = object
    workDoneProgress*: bool

  FoldingRangeRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  SelectionRangeOptions* = object
    workDoneProgress*: bool

  SelectionRangeRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  LinkedEditingRangeOptions* = object
    workDoneProgress*: bool

  LinkedEditingRangeRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  CallHierarchyOptions* = object
    workDoneProgress*: bool

  CallHierarchyRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  SemanticTokensLegend* = object
    tokenTypes*: seq[string]
    tokenModifiers*: seq[string]

  SemanticTokensOptions* = object
    workDoneProgress*: bool
    legend*: SemanticTokensLegend
    range*: bool # todo | {}
    full*: bool # todo | {delta?: boolean}

  SemanticTokensRegistrationOptions* = object
    workDoneProgress*: bool
    legend*: SemanticTokensLegend
    range*: bool # todo | {}
    full*: bool # todo | {delta?: boolean}
    documentSelector*: DocumentSelector
    id*: Option[string]

  MonikerOptions* = object
    workDoneProgress*: bool

  MonikerRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector

  TypeHierarchyOptions* = object
    workDoneProgress*: bool

  TypeHierarchyRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  InlineValueOptions* = object
    workDoneProgress*: bool

  InlineValueRegistrationOptions* = object
    workDoneProgress*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  InlineHintOptions* = object
    workDoneProgress*: bool
    resolveProvider*: bool

  InlineHintRegistrationOptions* = object
    workDoneProgress*: bool
    resolveProvider*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  DiagnosticOptions* = object
    workDoneProgress*: bool
    identifier*: Option[string]
    interFileDependencies*: bool
    workspaceDiagnostics*: bool

  DiagnosticRegistrationOptions* = object
    workDoneProgress*: bool
    identifier*: Option[string]
    interFileDependencies*: bool
    workspaceDiagnostics*: bool
    documentSelector*: DocumentSelector
    id*: Option[string]

  WorkspaceSymbolOptions* = object
    workDoneProgress*: bool
    resolveProvider*: bool

  WorkspaceFoldersServerCapabilities* = object
    supported*: Option[bool]
    changeNotifications*: Option[JsonNode]

  FileOperationPatternOptions* = object
    ignoreCase*: bool

  FileOperationPattern* = object
    glob*: string
    matches*: Option[FileOperationPatternKind]
    options*: Option[FileOperationPatternOptions]

  FileOperationFilter* = object
    scheme*: Option[string]
    pattern*: FileOperationPattern

  FileOperationRegistrationOptions* = object
    filters*: seq[FileOperationFilter]

  WorkspaceOptionsFileOperations* = object
    didCreate*: Option[FileOperationRegistrationOptions]
    willCreate*: Option[FileOperationRegistrationOptions]
    didRename*: Option[FileOperationRegistrationOptions]
    willRename*: Option[FileOperationRegistrationOptions]
    didDelete*: Option[FileOperationRegistrationOptions]
    willDelete*: Option[FileOperationRegistrationOptions]

  WorkspaceOptions* = object
    workspaceFolders*: Option[WorkspaceFoldersServerCapabilities]
    fileOperations*: Option[WorkspaceOptionsFileOperations]
    discard

  Position* = object
    line*: int
    character*: int

  Range* = object
    start*: Position
    `end`*: Position

  Location* = object
    uri*: string
    `range`*: Range

  LocationLink* = object
    originSelectionRange*: Option[Range]
    targetUri*: string
    targetRange*: Range
    targetSelectionRange*: Range

  TextDocumentIdentifier* = object
    uri*: string

  ProgressToken* = string

  CompletionContext* = object
    triggerKind*: CompletionTriggerKind
    triggerCharacter*: Option[string]

  CompletionItemLabelDetails* = object
    detail*: Option[string]
    description*: Option[string]

  MarkupContent* = object
    kind*: MarkupKind
    value*: string

  MarkedStringObject* = object
    language*: string
    value*: string

  TextEdit* = object
    `range`*: Range
    newText*: string

  InsertReplaceEdit* = object
    newText*: string
    insert*: Range
    replace*: Range

  Command* = object
    title*: string
    command*: string
    argument*: seq[JsonNode]

  WorkspaceFolder* = object
    uri*: string
    name*: string

  TextDocumentContentChangeEvent* = object
    range*: Range
    rangeLength*: Option[int]
    text*: string

variant(CompletionItemDocumentationVariant, string, MarkupContent)
variant(CompletionItemTextEditVariant, TextEdit, InsertReplaceEdit)
variant(MarkedStringVariant, string, MarkedStringObject)
variant(HoverContentVariant, MarkedStringVariant, seq[MarkedStringVariant], MarkupContent)

type
  CompletionItem* = object
    label*: string
    labelDetails*: Option[CompletionItemLabelDetails]
    kind*: CompletionKind
    tags*: seq[CompletionItemTag]
    detail*: Option[string]
    documentation*: Option[CompletionItemDocumentationVariant]
    deprecated*: Option[bool]
    preselect*: Option[bool]
    sortText*: Option[string]
    filterText*: Option[string]
    insertText*: Option[string]
    insertTextFormat*: Option[InsertTextFormat]
    insertTextMode*: Option[InsertTextMode]
    textEdit*: Option[CompletionItemTextEditVariant]
    textEditText*: Option[string]
    additionalTextEdits*: seq[TextEdit]
    commitCharacters*: seq[string]
    command*: seq[Command]
    data*: Option[JsonNode]

  CompletionList* = object
    isIncomplete*: bool
    itemDefaults*: bool # todo
    items*: seq[CompletionItem]

  SymbolKind* = enum
    File = 1
    Module = 2
    Namespace = 3
    Package = 4
    Class = 5
    Method = 6
    Property = 7
    Field = 8
    Constructor = 9
    Enum = 10
    Interface = 11
    Function = 12
    Variable = 13
    Constant = 14
    String = 15
    Number = 16
    Boolean = 17
    Array = 18
    Object = 19
    Key = 20
    Null = 21
    EnumMember = 22
    Struct = 23
    Event = 24
    Operator = 25
    TypeParameter = 26

  SymbolTag* = enum
    Deprecated = 1

  SymbolInformation* = object
    name*: string
    kind*: SymbolKind
    tags*: seq[SymbolTag]
    deprecated*: Option[bool]
    location*: Location
    containerName*: Option[string]

  DocumentSymbol* = object
    name*: string
    detail*: Option[string]
    kind*: SymbolKind
    tags*: seq[SymbolTag]
    deprecated*: Option[bool]
    range*: Range
    selectionRange*: Range
    children*: seq[DocumentSymbol]

type
  CompletionParams* = object
    workDoneProgress*: bool
    textDocument*: TextDocumentIdentifier
    position*: Position
    partialResultToken*: Option[ProgressToken]
    context: Option[CompletionContext]

  DefinitionParams* = object
    workDoneProgress*: bool
    textDocument*: TextDocumentIdentifier
    position*: Position
    partialResultToken*: Option[ProgressToken]

  DeclarationParams* = object
    workDoneProgress*: bool
    textDocument*: TextDocumentIdentifier
    position*: Position
    partialResultToken*: Option[ProgressToken]

  DocumentSymbolParams* = object
    workDoneProgress*: bool
    textDocument*: TextDocumentIdentifier
    partialResultToken*: Option[ProgressToken]

  DocumentHoverParams* = object
    workDoneProgress*: bool
    textDocument*: TextDocumentIdentifier
    position*: Position

  DocumentHoverResponse* = object
    contents*: HoverContentVariant
    range*: Option[Range]

variant(CompletionResponseVariant, seq[CompletionItem], CompletionList)
variant(DefinitionResponseVariant, Location, seq[Location], seq[LocationLink])
variant(DeclarationResponseVariant, Location, seq[Location], seq[LocationLink])
variant(DocumentSymbolResponseVariant, seq[DocumentSymbol], seq[SymbolInformation])
variant(DocumentHoverResponseVariant, seq[DocumentSymbol], seq[SymbolInformation])

type CompletionResponse* = CompletionResponseVariant
type DefinitionResponse* = DefinitionResponseVariant
type DeclarationResponse* = DeclarationResponseVariant
type DocumentSymbolResponse* = DocumentSymbolResponseVariant

variant(TextDocumentSyncVariant, TextDocumentSyncOptions, TextDocumentSyncKind)
variant(HoverProviderVariant, bool, HoverOptions)
variant(DeclarationVariant, bool, DeclarationOptions, DeclarationRegistrationOptions)
variant(DefinitionProviderVariant, bool, DefinitionOptions)
variant(TypeDefinitionProviderVariant, bool, TypeDefinitionOptions, TypeDefinitionRegistrationOptions)
variant(ImplementationProviderVariant, bool, ImplementationOptions, ImplementationRegistrationOptions)
variant(ReferencesProviderVariant, bool, ReferenceOptions)
variant(DocumentHighlightProviderVariant, bool, DocumentHighlightOptions)
variant(DocumentSymbolProviderVariant, bool, DocumentSymbolOptions)
variant(CodeActionProviderVariant, bool, CodeActionOptions)

variant(ColorProviderVariant, bool, DocumentColorOptions, DocumentColorRegistrationOptions)
variant(DocumentFormattingProviderVariant, bool, DocumentFormattingOptions)
variant(DocumentRangeFormattingProviderVariant, bool, DocumentRangeFormattingOptions)
variant(RenameProviderVariant, bool, RenameOptions)
variant(FoldingRangeProviderVariant, bool, FoldingRangeOptions, FoldingRangeRegistrationOptions)
variant(SelectionRangeProviderVariant, bool, SelectionRangeOptions, SelectionRangeRegistrationOptions)
variant(LinkedEditingRangeProviderVariant, bool, LinkedEditingRangeOptions, LinkedEditingRangeRegistrationOptions)
variant(CallHierarchyProviderVariant, bool, CallHierarchyOptions, CallHierarchyRegistrationOptions)
variant(SemanticTokensProviderVariant, SemanticTokensOptions, SemanticTokensRegistrationOptions)
variant(MonikerProviderVariant, bool, MonikerOptions, MonikerRegistrationOptions)
variant(TypeHierarchyProviderVariant, bool, TypeHierarchyOptions, TypeHierarchyRegistrationOptions)
variant(InlineValueProviderVariant, bool, InlineValueOptions, InlineValueRegistrationOptions)
variant(InlineHintProviderVariant, bool, InlineHintOptions, InlineHintRegistrationOptions)
variant(DiagnosticProviderVariant, DiagnosticOptions, DiagnosticRegistrationOptions)
variant(WorkspaceSymbolProviderVariant, bool, WorkspaceSymbolOptions)

type
  ServerCapabilities* = object
    positionEncoding*: Option[PositionEncodingKind]
    textDocumentSync*: Option[TextDocumentSyncVariant]
    # nodebookDocumentSync*: Option[]
    completionProvider*: Option[CompletionOptions]
    hoverProvider*: Option[HoverProviderVariant]
    signatureHelpProvider*: Option[SignatureHelpOptions]
    declarationProvider*: Option[DeclarationVariant]
    definitionProvider*: Option[DefinitionProviderVariant]
    typeDefinitionProvider*: Option[TypeDefinitionProviderVariant]
    implementationProvider*: Option[ImplementationProviderVariant]
    referencesProvider*: Option[ReferencesProviderVariant]
    documentHighlightProvider*: Option[DocumentHighlightProviderVariant]
    documentSymbolProvider*: Option[DocumentSymbolProviderVariant]
    codeActionProvider*: Option[CodeActionProviderVariant]
    codeLensProvider*: Option[CodeLensOptions]
    documentLinkProvider*: Option[DocumentLinkOptions]
    colorProvider*: Option[ColorProviderVariant]
    documentFormattingProvider*: Option[DocumentFormattingProviderVariant]
    documentRangeFormattingProvider*: Option[DocumentRangeFormattingProviderVariant]
    documentOnTypeFormattingProvider*: Option[DocumentOnTypeFormattingOptions]
    renameProvider*: Option[RenameProviderVariant]
    foldingRangeProvider*: Option[FoldingRangeProviderVariant]
    executeCommandProvider*: Option[ExecuteCommandOptions]
    selectionRangeProvider*: Option[SelectionRangeProviderVariant]
    linkedEditingRangeProvider*: Option[LinkedEditingRangeProviderVariant]
    callHierarchyProvider*: Option[CallHierarchyProviderVariant]
    semanticTokensProvider*: Option[SemanticTokensProviderVariant]
    monikerProvider*: Option[MonikerProviderVariant]
    typeHierarchyProvider*: Option[TypeHierarchyProviderVariant]
    inlineValueProvider*: Option[InlineValueProviderVariant]
    inlineHintProvider*: Option[InlineHintProviderVariant]
    diagnosticProvider*: Option[DiagnosticProviderVariant]
    workspaceSymbolProvider*: Option[WorkspaceSymbolProviderVariant]
    workspace*: Option[WorkspaceOptions]
    # experimental*: Option[JsonNode]

type
  ResponseKind* {.pure.} = enum
    Error
    Success

  ResponseError* = object
    code*: int
    message*: string
    data*: JsonNode

  Response*[T] = object
    id*: int
    case kind*: ResponseKind
    of Error:
      error*: ResponseError
    of Success:
      result*: T

proc to*(a: Response[JsonNode], T: typedesc): Response[T] =
  when T is JsonNode:
    return a
  else:
    case a.kind:
    of ResponseKind.Error:
      return Response[T](id: a.id, kind: ResponseKind.Error, error: a.error)
    of ResponseKind.Success:
      try:
        return Response[T](id: a.id, kind: ResponseKind.Success, result: a.result.jsonTo(T, Joptions(allowMissingKeys: true, allowExtraKeys: true)))
      except:
        let error = ResponseError(code: -2, message: "Failed to convert result to " & $T, data: a.result)
        return Response[T](id: a.id, kind: ResponseKind.Error, error: error)

proc to*[K](a: Response[K], T: typedesc): Response[T] =
  when T is JsonNode:
    return a
  else:
    case a.kind:
    of ResponseKind.Error:
      return Response[T](id: a.id, kind: ResponseKind.Error, error: a.error)
    of ResponseKind.Success:
      assert false

proc fromJsonHook*[T](a: var Response[T], b: JsonNode, opt = Joptions()) =
  if b.hasKey("error"):
    a = Response[T](id: b["id"].getInt, kind: ResponseKind.Error, error: b["error"].jsonTo(ResponseError, Joptions(allowMissingKeys: true, allowExtraKeys: true)))
  else:
    a = Response[JsonNode](id: b["id"].getInt, kind: ResponseKind.Success, result: b["result"]).to T

proc toResponse*(node: JsonNode, T: typedesc): Response[T] =
  fromJsonHook[T](result, node)

proc success*[T](value: T): Response[T] =
  return Response[T](kind: ResponseKind.Success, result: value)

proc error*[T](code: int, message: string, data: JsonNode = newJNull()): Response[T] =
  return Response[T](kind: ResponseKind.Error, error: ResponseError(code: code, message: message, data: data))

proc isSuccess*[T](response: Response[T]): bool = response.kind == ResponseKind.Success
proc isError*[T](response: Response[T]): bool = response.kind == ResponseKind.Error