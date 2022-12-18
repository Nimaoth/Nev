import json, strutils, tables, options, macros
import myjsonutils

type
  PositionEncodingKind* = enum
    UTF8 = "utf-8"
    UTF16 = "utf-16"
    UTF32 = "utf-32"

  TextDocumentSyncKind* = enum
    None = 0
    Full = 1
    Incremental = 2

  CodeActionKind* = enum
    Empty = ""
    QuickFix = "quickfix"
    Refactor = "refactor"
    RefactorExtract = "refactor.extract"
    RefactorInline = "refactor.inline"
    RefactorRewrite = "refactor.rewrite"
    Source = "source"
    SourceOrganizeImports = "source.organizeImports"
    SourceFixAll = "source.fixAll"

  FileOperationPatternKind* {.pure.} = enum
    File = "file"
    Folder = "folder"

  TextDocumentSyncOptions* = object
    openClose*: bool
    change*: TextDocumentSyncKind

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
    supported*: bool
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

macro variant(name: untyped, types: varargs[untyped]): untyped =
  # defer:
  #   # echo result.treeRepr
  #   echo result.repr

  var variantType = quote do:
    type `name`* = object
      node: JsonNode

  var procs = nnkStmtList.newTree
  for t in types:
    let procName = ident("as" & t.strVal.capitalizeAscii)
    procs.add quote do:
      proc `procName`*(arg: `name`): Option[`t`] =
        try:
          return arg.node.jsonTo(`t`, Joptions(allowMissingKeys: true, allowExtraKeys: true)).some
        except:
          return `t`.none
      proc `procName`*(arg: Option[`name`]): Option[`t`] =
        if arg.isSome:
          return `procName`(arg.get)
        else:
          return `t`.none

  return quote do:
    `variantType`
    `procs`
    proc fromJsonHook*(a: var `name`, b: JsonNode, opt = Joptions()) =
      a.node = b

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
    experimental*: Option[JsonNode]