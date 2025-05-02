import std/[json, strutils, tables, options, macros, genasts]
import misc/[myjsonutils, response]

proc fromJsonHook*[T](a: var Response[T], b: JsonNode, opt = Joptions()) =
  if b.hasKey("error"):
    a = Response[T](
      id: b["id"].getInt,
      kind: ResponseKind.Error,
      error: b["error"].jsonTo(ResponseError, Joptions(allowMissingKeys: true, allowExtraKeys: true)),
    )
  else:
    a = Response[JsonNode](id: b["id"].getInt, kind: ResponseKind.Success, result: b["result"]).to T

proc toResponse*(node: JsonNode, T: typedesc): Response[T] =
  fromJsonHook[T](result, node)

macro variant(name: untyped, types: varargs[untyped]): untyped =
  var variantType = quote do:
    type `name`* = object
      node*: JsonNode

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

      proc procName*(arg: name): Option[t] {.gcsafe, raises: [].} =
        try:
          when isSeqLit:
            if arg.node.kind != JArray:
              return t.none
          return arg.node.jsonTo(t, Joptions(allowMissingKeys: true, allowExtraKeys: false)).some
        except:
          return t.none

      proc procName*(arg: Option[name]): Option[t] {.gcsafe, raises: [].} =
        if arg.isSome:
          return procName(arg.get)
        else:
          return t.none

      proc init*(_: typedesc[name], arg: t): name =
        return name(node: arg.toJson)

    procs.add ast

  return quote do:
    `variantType`
    `procs`
    proc fromJsonHook*(a: var `name`, b: JsonNode, opt = Joptions()) =
      a.node = b
    proc toJsonHook*(a: `name`): JsonNode =
      return a.node

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

  CodeActionTriggerKind* {.pure.} = enum
    Invoked = 1
    Automatic = 2

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

  InlayHintKind* {.pure.} = enum
    Type = 1
    Parameter = 2

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
    save*: JsonNode

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

  InlayHintOptions* = object
    workDoneProgress*: bool
    resolveProvider*: bool

  InlayHintRegistrationOptions* = object
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

  WorkspaceEdit* = object
    changes*: Option[JsonNode]
    documentChanges*: Option[JsonNode]
    changeAnnotations*: Option[JsonNode]

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
    text*: string

  UriObject* = object
    uri*: string

variant(CompletionItemDocumentationVariant, string, MarkupContent)
variant(CompletionItemTextEditVariant, TextEdit, InsertReplaceEdit)
variant(MarkedStringVariant, string, MarkedStringObject)
variant(HoverContentVariant, MarkedStringVariant, seq[MarkedStringVariant], MarkupContent)
variant(WorkspaceLocationVariant, Location, UriObject)

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
    score*: Option[float]
    data*: Option[JsonNode]

  CompletionList* = object
    isIncomplete*: bool
    itemDefaults*: Option[JsonNode] = JsonNode.none
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
    containerName*: Option[string]
    location*: Location
    score*: Option[float]
    deprecated*: Option[bool]

  WorkspaceSymbol* = object
    name*: string
    kind*: SymbolKind
    tags*: seq[SymbolTag]
    containerName*: Option[string]
    location*: WorkspaceLocationVariant
    data*: Option[JsonNode]

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
    context*: Option[CompletionContext]

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

  TypeDefinitionParams* = object
    workDoneProgress*: bool
    textDocument*: TextDocumentIdentifier
    position*: Position
    partialResultToken*: Option[ProgressToken]

  ImplementationParams* = object
    workDoneProgress*: bool
    textDocument*: TextDocumentIdentifier
    position*: Position
    partialResultToken*: Option[ProgressToken]

  ReferenceContext* = object
    includeDeclaration*: bool

  ReferenceParams* = object
    workDoneProgress*: bool
    textDocument*: TextDocumentIdentifier
    position*: Position
    context*: ReferenceContext
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

  WorkspaceSymbolParams* = object
    workDoneProgress*: bool
    partialResultToken*: Option[ProgressToken]
    query*: string

  InlayHintParams* = object
    workDoneProgress*: bool
    textDocument*: TextDocumentIdentifier
    range*: Range

  InlayHint* = object
    position*: Position
    label*: JsonNode # string # | InlayHintLabelPart[] # todo
    kind*: Option[InlayHintKind]
    textEdits*: seq[TextEdit]
    tooltip*: JsonNode # Option[string] # | MarkupContent # todo
    paddingLeft*: Option[bool]
    paddingRight*: Option[bool]
    data*: Option[JsonNode]

  DocumentDiagnosticReportKind* {.pure.} = enum
    Full = "full"
    Unchanged = "unchanged"

  DiagnosticSeverity* {.pure.} = enum
    Error = 1
    Warning = 2
    Information = 3
    Hint = 4

  CodeDescription* = object
    href*: string

  DiagnosticTag* {.pure.} = enum
    Unnessessary = 1
    Deprecated = 2

  DiagnosticRelatedInformation* = object
    location*: Location
    message*: string

  Diagnostic* = object
    `range`*: Range
    severity*: Option[DiagnosticSeverity]
    code*: Option[JsonNode]
    codeDescription*: CodeDescription
    source*: Option[string]
    message*: string
    tags*: seq[DiagnosticTag]
    relatedInformation*: Option[seq[DiagnosticRelatedInformation]]
    data*: Option[JsonNode]

  RelatedFullDocumentDiagnosticReport* = object
    kind*: DocumentDiagnosticReportKind
    resultId*: Option[string]
    items*: seq[Diagnostic]

  RelatedUnchangedDocumentDiagnosticReport* = object
    kind*: DocumentDiagnosticReportKind
    resultId*: string

  PublicDiagnosticsParams* = object
    uri*: string
    version*: Option[int] = int.none
    diagnostics*: seq[Diagnostic]

  ConfigurationItem* = object
    scopeUri*: Option[string] = string.none
    section*: Option[string] = string.none

  ConfigurationParams* = object
    items*: seq[ConfigurationItem]

  CodeActionContext* = object
    diagnostics*: seq[Diagnostic]
    only*: Option[seq[CodeActionKind]]
    triggerKind*: Option[CodeActionTriggerKind]

  CodeAction* = object
    title*: string
    kind*: Option[CodeActionKind]
    diagnostics*: Option[seq[Diagnostic]]
    isPreferred*: Option[bool]
    disabled*: Option[tuple[reason: string]]
    edit*: Option[WorkspaceEdit]
    command*: Option[Command]
    data*: Option[JsonNode]

  CodeActionParams* = object
    textDocument*: TextDocumentIdentifier
    `range`*: Range
    context*: CodeActionContext

variant(CompletionResponseVariant, seq[CompletionItem], CompletionList)
variant(DefinitionResponseVariant, Location, seq[Location], seq[LocationLink])
variant(DeclarationResponseVariant, Location, seq[Location], seq[LocationLink])
variant(TypeDefinitionResponseVariant, Location, seq[Location], seq[LocationLink])
variant(ImplementationResponseVariant, Location, seq[Location], seq[LocationLink])
variant(ReferenceResponseVariant, seq[Location])
variant(DocumentSymbolResponseVariant, seq[DocumentSymbol], seq[SymbolInformation])
variant(DocumentHoverResponseVariant, seq[DocumentSymbol], seq[SymbolInformation])
variant(DocumentDiagnosticResponse, RelatedFullDocumentDiagnosticReport, RelatedUnchangedDocumentDiagnosticReport)
variant(WorkspaceSymbolResponseVariant, seq[WorkspaceSymbol], seq[SymbolInformation])
variant(CodeActionResponseVariant, Command, CodeAction)

type CompletionResponse* = CompletionResponseVariant
type DefinitionResponse* = DefinitionResponseVariant
type DeclarationResponse* = DeclarationResponseVariant
type TypeDefinitionResponse* = TypeDefinitionResponseVariant
type ImplementationResponse* = ImplementationResponseVariant
type ReferenceResponse* = ReferenceResponseVariant
type DocumentSymbolResponse* = DocumentSymbolResponseVariant
type InlayHintResponse* = Option[seq[InlayHint]]
type WorkspaceSymbolResponse* = WorkspaceSymbolResponseVariant
type CodeActionResponse* = seq[CodeActionResponseVariant]

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
variant(InlayHintProviderVariant, bool, InlayHintOptions, InlayHintRegistrationOptions)
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
    inlayHintProvider*: Option[InlayHintProviderVariant]
    diagnosticProvider*: Option[DiagnosticProviderVariant]
    workspaceSymbolProvider*: Option[WorkspaceSymbolProviderVariant]
    workspace*: Option[WorkspaceOptions]
    # experimental*: Option[JsonNode]
