import misc/id
import ast/model

# base language

const IdBaseInterfaces* = "656f7f67d077504f640d8716".parseId.LanguageId
const IdBaseLanguage* = "62e53399564d29f77293450e".parseId.LanguageId

const IdPrint* = "62e53396564d29f7729344f7".parseId.ClassId
const IdAdd* = "62e53396564d29f7729344f8".parseId.ClassId
const IdSub* = "62e53396564d29f7729344f9".parseId.ClassId
const IdMul* = "62e53396564d29f7729344fa".parseId.ClassId
const IdDiv* = "62e53397564d29f7729344fb".parseId.ClassId
const IdMod* = "62e53397564d29f7729344fc".parseId.ClassId
const IdNegate* = "62e53397564d29f7729344fd".parseId.ClassId
const IdNot* = "62e53397564d29f7729344fe".parseId.ClassId
const IdAppendString* = "62e53397564d29f772934500".parseId.ClassId
const IdLess* = "62e53398564d29f772934504".parseId.ClassId
const IdLessEqual* = "62e53398564d29f772934505".parseId.ClassId
const IdGreater* = "62e53398564d29f772934506".parseId.ClassId
const IdGreaterEqual* = "62e53398564d29f772934507".parseId.ClassId
const IdEqual* = "62e53398564d29f772934508".parseId.ClassId
const IdNotEqual* = "62e53398564d29f772934509".parseId.ClassId
const IdAnd* = "62e53398564d29f77293450a".parseId.ClassId
const IdOr* = "62e53398564d29f77293450b".parseId.ClassId
const IdOrder* = "62e53398564d29f77293450c".parseId.ClassId
const IdBuildString* = "62e53399564d29f77293450d".parseId.ClassId

const IdType* = "62e53399564d29f77293450f".parseId.ClassId
const IdString* = "62e53397564d29f772934502".parseId.ClassId
const IdInt32* = "62e53397564d29f772934501".parseId.ClassId
const IdInt64* = "654fbb281446e19b3822525c".parseId.ClassId
const IdUInt32* = "654fbb281446e19b3822525d".parseId.ClassId
const IdUInt64* = "654fbb281446e19b3822525e".parseId.ClassId
const IdFloat32* = "654fbb281446e19b3822525f".parseId.ClassId
const IdFloat64* = "654fbb281446e19b38225260".parseId.ClassId
const IdVoid* = "62e53397564d29f772934503".parseId.ClassId
const IdChar* = "654fbb281446e19b38225262".parseId.ClassId

const IdMetaTypeInstance* = "656f7f67d077504f640d86cd".parseId.NodeId #  IdType
const IdStringTypeInstance* = "656f7f67d077504f640d86ce".parseId.NodeId #  IdString
const IdInt32TypeInstance* = "656f7f67d077504f640d86cf".parseId.NodeId # IdInt32
const IdUint32TypeInstance* = "656f7f67d077504f640d86d0".parseId.NodeId # IdInt64
const IdInt64TypeInstance* = "656f7f67d077504f640d86d1".parseId.NodeId # IdUInt32
const IdUint64TypeInstance* = "656f7f67d077504f640d86d2".parseId.NodeId # IdUInt64
const IdFloat32TypeInstance* = "656f7f67d077504f640d86d3".parseId.NodeId # IdFloat32
const IdFloat64TypeInstance* = "656f7f67d077504f640d86d4".parseId.NodeId # IdFloat64
const IdVoidTypeInstance* = "656f7f67d077504f640d86d5".parseId.NodeId # IdVoid
const IdCharTypeInstance* = "656f7f67d077504f640d86d6".parseId.NodeId # IdChar

const IdFunctionType* = "62e5339a564d29f77293451c".parseId.ClassId
const IdFunctionTypeReturnType* = "62e53399564d29f772934510".parseId.RoleId
const IdFunctionTypeParameterTypes* = "62e53399564d29f772934511".parseId.RoleId

const IdFunctionImport* = "656f7f67d077504f640d8713".parseId.ClassId
const IdFunctionImportName* = "656f7f67d077504f640d8714".parseId.RoleId
const IdFunctionImportType* = "656f7f67d077504f640d8715".parseId.RoleId

const IdCast* = "654fbb281446e19b38225261".parseId.ClassId
const IdCastType* = "654fbb281446e19b38225262".parseId.RoleId
const IdCastValue* = "656f7f67d077504f640d86c9".parseId.RoleId

const IdPrintArguments* = "62e5339a564d29f772934518".parseId.RoleId
const IdBuildArguments* = "62e5339a564d29f772934519".parseId.RoleId

const IdUnaryExpression* = "62e5339a564d29f77293451a".parseId.ClassId
const IdUnaryExpressionChild* = "62e5339a564d29f77293451b".parseId.RoleId

const IdIDeclaration* = "62e5339a564d29f77293451d".parseId.ClassId

const IdBreakExpression* = "62e5339b564d29f772934520".parseId.ClassId
const IdContinueExpression* = "62e5339b564d29f772934521".parseId.ClassId
const IdReturnExpression* = "62e5339b564d29f772934522".parseId.ClassId
const IdReturnExpressionValue* = "656f7f67d077504f640d8719".parseId.RoleId

const IdEmptyLine* = "62e5339b564d29f772934526".parseId.ClassId

const IdBlockChildren* = "62e5339b564d29f772934527".parseId.RoleId
const IdBlock* = "62e5339b564d29f772934528".parseId.ClassId

const IdINamedName* = "62e5339c564d29f772934529".parseId.RoleId
const IdINamed* = "62e5339c564d29f77293452a".parseId.ClassId

const IdAssignmentValue* = "62e5339c564d29f77293452b".parseId.RoleId
const IdAssignmentTarget* = "62e5339c564d29f77293452c".parseId.RoleId
const IdAssignment* = "62e5339c564d29f77293452d".parseId.ClassId

const IdFunctionDefinitionBody* = "62e5339c564d29f77293452e".parseId.RoleId
const IdFunctionDefinitionReturnType* = "62e5339c564d29f77293452f".parseId.RoleId
const IdFunctionDefinitionParameters* = "62e5339c564d29f772934530".parseId.RoleId
const IdFunctionDefinition* = "62e5339c564d29f772934531".parseId.ClassId

const IdParameterDeclValue* = "62e5339d564d29f772934532".parseId.RoleId
const IdParameterDeclType* = "62e5339d564d29f772934533".parseId.RoleId
const IdParameterDecl* = "62e5339d564d29f772934535".parseId.ClassId

const IdILoop* = "654fbb281446e19b3822525a".parseId.ClassId

const IdWhileExpressionBody* = "62e5339d564d29f772934536".parseId.RoleId
const IdWhileExpressionCondition* = "62e5339d564d29f772934537".parseId.RoleId
const IdWhileExpression* = "62e5339d564d29f772934538".parseId.ClassId

const IdForLoop* = "654fbb281446e19b38225256".parseId.ClassId
const IdForLoopVariable* = "654fbb281446e19b3822525b".parseId.RoleId
const IdForLoopStart* = "654fbb281446e19b38225258".parseId.RoleId
const IdForLoopEnd* = "654fbb281446e19b38225259".parseId.RoleId
const IdForLoopBody* = "654fbb281446e19b38225257".parseId.RoleId

const IdIfExpressionElseCase* = "62e5339d564d29f772934539".parseId.RoleId
const IdIfExpressionThenCase* = "62e5339d564d29f77293453a".parseId.RoleId
const IdThenCase* = "62e5339a564d29f77293451f".parseId.ClassId
const IdThenCaseCondition* = "62e5339e564d29f77293453b".parseId.RoleId
const IdThenCaseBody* = "62e5339a564d29f77293451e".parseId.RoleId
const IdIfExpression* = "62e5339e564d29f77293453c".parseId.ClassId

const IdCallArguments* = "62e5339e564d29f77293453d".parseId.RoleId
const IdCallFunction* = "62e5339e564d29f77293453e".parseId.RoleId
const IdCall* = "62e5339e564d29f77293453f".parseId.ClassId

const IdNodeListChildren* = "62e5339e564d29f772934540".parseId.RoleId
const IdNodeList* = "62e5339e564d29f772934541".parseId.ClassId

const IdVarDeclValue* = "62e5339e564d29f772934542".parseId.RoleId
const IdVarDeclType* = "62e5339e564d29f772934543".parseId.RoleId
const IdVarDecl* = "62e5339f564d29f772934545".parseId.ClassId

const IdLetDeclValue* = "62e5339f564d29f772934546".parseId.RoleId
const IdLetDeclType* = "62e5339f564d29f772934547".parseId.RoleId
const IdLetDecl* = "62e5339f564d29f772934549".parseId.ClassId

const IdConstDeclValue* = "62e5339f564d29f77293454a".parseId.RoleId
const IdConstDeclType* = "62e5339f564d29f77293454b".parseId.RoleId
const IdConstDecl* = "62e5339f564d29f77293454d".parseId.ClassId

const IdEmpty* = "62e533a0564d29f77293454e".parseId.ClassId

const IdNodeReferenceTarget* = "62e533a0564d29f77293454f".parseId.RoleId
const IdNodeReference* = "62e533a0564d29f772934550".parseId.ClassId

const IdBinaryExpressionLeft* = "62e533a0564d29f772934551".parseId.RoleId
const IdBinaryExpressionRight* = "62e533a0564d29f772934552".parseId.RoleId
const IdBinaryExpression* = "62e533a0564d29f772934553".parseId.ClassId

const IdExpression* = "62e533a0564d29f772934554".parseId.ClassId

const IdBoolLiteralValue* = "62e533a0564d29f772934555".parseId.RoleId
const IdBoolLiteral* = "62e533a0564d29f772934556".parseId.ClassId

const IdStringLiteralValue* = "62e533a1564d29f772934557".parseId.RoleId
const IdStringLiteral* = "62e533a1564d29f772934558".parseId.ClassId

const IdIntegerLiteralValue* = "62e533a1564d29f772934559".parseId.RoleId
const IdIntegerLiteral* = "62e533a1564d29f77293455a".parseId.ClassId

const IdStructDefinition* = "654fbb281446e19b38225201".parseId.ClassId
const IdStructDefinitionMembers* = "654fbb281446e19b38225202".parseId.RoleId
const IdStructDefinitionParameter* = "654fbb281446e19b38225207".parseId.RoleId

const IdStructParameter* = "654fbb281446e19b38225217".parseId.ClassId
const IdStructParameterType* = "654fbb281446e19b38225215".parseId.RoleId
const IdStructParameterValue* = "654fbb281446e19b38225218".parseId.RoleId

const IdStructMemberDefinition* = "654fbb281446e19b38225203".parseId.ClassId
const IdStructMemberDefinitionType* = "654fbb281446e19b38225205".parseId.RoleId
const IdStructMemberDefinitionValue* = "654fbb281446e19b38225206".parseId.RoleId

const IdStructType* = "654fbb281446e19b38225204".parseId.ClassId
const IdStructTypeMemberTypes* = "654fbb281446e19b38225207".parseId.RoleId
const IdStructTypeGenericMember* = "654fbb281446e19b38225218".parseId.RoleId
const IdStructTypeGenericBase* = "654fbb281446e19b38225219".parseId.RoleId

const IdStructMemberAccess* = "654fbb281446e19b3822520a".parseId.ClassId
const IdStructMemberAccessMember* = "654fbb281446e19b38225208".parseId.RoleId
const IdStructMemberAccessValue* = "654fbb281446e19b38225209".parseId.RoleId

const IdPointerTypeDecl* = "62e5339b564d29f772934523".parseId.ClassId
const IdPointerTypeDeclTarget* = "62e5339b564d29f772934524".parseId.RoleId

const IdPointerType* = "656f7f67d077504f640d86ca".parseId.ClassId
const IdPointerTypeTarget* = "656f7f67d077504f640d86cb".parseId.RoleId

const IdAddressOf* = "62e5339b564d29f772934525".parseId.ClassId
const IdAddressOfValue* = "654fbb281446e19b3822520b".parseId.RoleId
const IdDeref* = "654fbb281446e19b3822520c".parseId.ClassId
const IdDerefValue* = "654fbb281446e19b3822520d".parseId.RoleId

const IdArrayAccess* = "654fbb281446e19b3822520e".parseId.ClassId
const IdArrayAccessValue* = "654fbb281446e19b3822520f".parseId.RoleId
const IdArrayAccessIndex* = "654fbb281446e19b38225210".parseId.RoleId

const IdAllocate* = "654fbb281446e19b38225211".parseId.ClassId
const IdAllocateType* = "654fbb281446e19b38225212".parseId.RoleId
const IdAllocateCount* = "654fbb281446e19b38225213".parseId.RoleId

const IdGenericType* = "654fbb281446e19b3822521a".parseId.ClassId
const IdGenericTypeValue* = "654fbb281446e19b3822521b".parseId.RoleId

const IdStringGetPointer* = "654fbb281446e19b38225252".parseId.ClassId
const IdStringGetPointerValue* = "654fbb281446e19b38225253".parseId.RoleId

const IdStringGetLength* = "654fbb281446e19b38225254".parseId.ClassId
const IdStringGetLengthValue* = "654fbb281446e19b38225255".parseId.RoleId

# lang language
const IdLangLanguage* = "654fbb281446e19b3822523f".parseId.LanguageId

const IdLangRoot* = "654fbb281446e19b3822524f".parseId.ClassId
const IdLangRootChildren* = "654fbb281446e19b38225250".parseId.RoleId

const IdLangAspect* = "654fbb281446e19b38225251".parseId.ClassId

const IdClassDefinition* = "654fbb281446e19b3822522a".parseId.ClassId
const IdClassDefinitionAbstract* = "654fbb281446e19b38225236".parseId.RoleId
const IdClassDefinitionInterface* = "654fbb281446e19b38225239".parseId.RoleId
const IdClassDefinitionFinal* = "654fbb281446e19b38225248".parseId.RoleId
const IdClassDefinitionCanBeRoot* = "654fbb281446e19b3822524b".parseId.RoleId
const IdClassDefinitionBaseClass* = "654fbb281446e19b38225237".parseId.RoleId
const IdClassDefinitionInterfaces* = "654fbb281446e19b3822523a".parseId.RoleId
const IdClassDefinitionAlias* = "654fbb281446e19b38225238".parseId.RoleId
const IdClassDefinitionSubstitutionProperty* = "654fbb281446e19b38225249".parseId.RoleId
const IdClassDefinitionSubstitutionReference* = "656f7f67d077504f640d8717".parseId.RoleId
const IdClassDefinitionPrecedence* = "654fbb281446e19b3822524a".parseId.RoleId

const IdClassDefinitionProperties* = "654fbb281446e19b3822522b".parseId.RoleId
const IdClassDefinitionReferences* = "654fbb281446e19b3822522c".parseId.RoleId
const IdClassDefinitionChildren* = "654fbb281446e19b3822522d".parseId.RoleId

const IdPropertyDefinition* = "654fbb281446e19b3822522e".parseId.ClassId
const IdPropertyDefinitionType* = "654fbb281446e19b3822522f".parseId.RoleId

const IdReferenceDefinition* = "654fbb281446e19b38225230".parseId.ClassId
const IdReferenceDefinitionClass* = "654fbb281446e19b38225231".parseId.RoleId
const IdReferenceDefinitionCount* = "654fbb281446e19b38225232".parseId.RoleId

const IdChildrenDefinition* = "654fbb281446e19b38225233".parseId.ClassId
const IdChildrenDefinitionClass* = "654fbb281446e19b38225234".parseId.RoleId
const IdChildrenDefinitionCount* = "654fbb281446e19b38225235".parseId.RoleId

const IdPropertyType* = "654fbb281446e19b3822523b".parseId.ClassId
const IdPropertyTypeBool* = "654fbb281446e19b3822523c".parseId.ClassId
const IdPropertyTypeString* = "654fbb281446e19b3822523d".parseId.ClassId
const IdPropertyTypeNumber* = "654fbb281446e19b3822523e".parseId.ClassId

const IdCount* = "654fbb281446e19b38225243".parseId.ClassId
const IdCountZeroOrOne* = "654fbb281446e19b38225244".parseId.ClassId
const IdCountOne* = "654fbb281446e19b38225245".parseId.ClassId
const IdCountZeroOrMore* = "654fbb281446e19b38225246".parseId.ClassId
const IdCountOneOrMore* = "654fbb281446e19b38225247".parseId.ClassId

const IdClassReference* = "654fbb281446e19b38225241".parseId.ClassId
const IdClassReferenceTarget* = "654fbb281446e19b38225242".parseId.RoleId

const IdRoleReference* = "654fbb281446e19b3822524d".parseId.ClassId
const IdRoleReferenceTarget* = "654fbb281446e19b3822524e".parseId.RoleId

const IdIRoleDescriptor* = "654fbb281446e19b3822524c".parseId.ClassId

# cell language

const IdCellLanguage* = "82ffffff9afd1f08150838c9".parseId.LanguageId
const IdCellBuilderDefinition* = "82ffffff9afd1f08150838f7".parseId.ClassId
const IdCellBuilderDefinitionClass* = "82ffffff0cfb77255e939d35".parseId.RoleId
const IdCellBuilderDefinitionOnlyExactMatch* = "84ffffff2644c27942bd153c".parseId.RoleId
const IdCellBuilderDefinitionCellDefinitions* = "82ffffffb1fee44425c76425".parseId.RoleId
const IdCellDefinition* = "82ffffffeb36250369ecc38d".parseId.ClassId
const IdCellDefinitionCellFlags* = "83ffffff2ff1f3327cb46f5e".parseId.RoleId
const IdCellDefinitionForegroundColor* = "84ffffff2644c27942bd33c5".parseId.RoleId
const IdCellDefinitionBackgroundColor* = "84ffffff2644c27942bd3ad1".parseId.RoleId
const IdCellDefinitionShadowText* = "83ffffff5072ba5455ab0899".parseId.RoleId
const IdCollectionCellDefinition* = "82ffffffeb36250369ecc453".parseId.ClassId
const IdCollectionCellDefinitionChildren* = "82ffffffb1fee44425c74de5".parseId.RoleId
const IdHorizontalCellDefinition* = "82ffffffeb36250369ecc6f4".parseId.ClassId
const IdVerticalCellDefinition* = "82ffffff65d17c4d369b48fc".parseId.ClassId
const IdConstantCellDefinition* = "82ffffffb1fee44425c73d48".parseId.ClassId
const IdConstantCellDefinitionText* = "82ffffffb1fee44425c74b10".parseId.RoleId
const IdPropertyCellDefinition* = "82ffffffb1fee44425c74037".parseId.ClassId
const IdPropertyCellDefinitionRole* = "83ffffff7b692e136c254962".parseId.RoleId
const IdReferenceCellDefinition* = "82ffffffb1fee44425c74370".parseId.ClassId
const IdReferenceCellDefinitionRole* = "83ffffff6502967277395168".parseId.RoleId
const IdReferenceCellDefinitionTargetProperty* = "84ffffff8ded04333b862793".parseId.RoleId
const IdChildrenCellDefinition* = "82ffffffb1fee44425c7489e".parseId.ClassId
const IdChildrenCellDefinitionRole* = "83ffffff65029672773954de".parseId.RoleId
const IdAliasCellDefinition* = "83ffffffd56370322839bd98".parseId.ClassId

const IdColorDefinition* = "84ffffff2644c27942bd1b3d".parseId.ClassId
const IdColorDefinitionText* = "84ffffff2644c27942bd1ed1".parseId.ClassId
const IdColorDefinitionTextScope* = "84ffffff2644c27942bd2283".parseId.RoleId

const IdCellFlag* = "83ffffff2ff1f3327cb4690a".parseId.ClassId
const IdCellFlagDeleteWhenEmpty* = "83ffffff2ff1f3327cb46bf6".parseId.ClassId
const IdCellFlagOnNewLine* = "83ffffff30ca3e3e3f8f79a5".parseId.ClassId
const IdCellFlagIndentChildren* = "83ffffff30ca3e3e3f8f7c46".parseId.ClassId
const IdCellFlagNoSpaceLeft* = "83ffffff30ca3e3e3f8f7f2d".parseId.ClassId
const IdCellFlagNoSpaceRight* = "83ffffff30ca3e3e3f8f825a".parseId.ClassId
const IdCellFlagVertical* = "83ffffffa9e6fd006c2f6ac4".parseId.ClassId
const IdCellFlagHorizontal* = "83ffffffa9e6fd006c2f7076".parseId.ClassId
const IdCellFlagDisableEditing* = "83ffffff0fe70c0b7dabe774".parseId.ClassId
const IdCellFlagDisableSelection* = "83ffffff0fe70c0b7dabeb0c".parseId.ClassId
const IdCellFlagDeleteNeighbor* = "83ffffff0fe70c0b7dabff35".parseId.ClassId

# property validator language

const IdPropertyValidatorLanguage* = "8cffffff484c682b4a6c4637".parseId.LanguageId
const IdPropertyValidatorDefinition* = "8cffffff484c682b4a6c4667".parseId.ClassId
const IdPropertyValidatorDefinitionClass* = "8cffffff2061f8026045266e".parseId.RoleId
const IdPropertyValidatorDefinitionProperty* = "8cffffff2061f80260452a12".parseId.RoleId
const IdPropertyValidatorDefinitionImplementation* = "8dffffffba19ff0d0d9c348c".parseId.RoleId

# scope language

const IdScopeLanguage* = "bbffffff26a84d413cfea9d3".parseId.LanguageId
const IdScopeDefinition* = "bbffffff26a84d413cfeaa09".parseId.ClassId
const IdScopeDefinitionClass* = "bbffffff924688011c5477fd".parseId.RoleId
const IdScopeDefinitionImplementation* = "bbffffff924688011c547871".parseId.RoleId

# new ids



const Id656f7f67d077504f640d86d7* = "656f7f67d077504f640d86d7".parseId
const Id656f7f67d077504f640d86d8* = "656f7f67d077504f640d86d8".parseId
const Id656f7f67d077504f640d86d9* = "656f7f67d077504f640d86d9".parseId
const Id656f7f67d077504f640d86da* = "656f7f67d077504f640d86da".parseId
const Id656f7f67d077504f640d86db* = "656f7f67d077504f640d86db".parseId
const Id656f7f67d077504f640d86dc* = "656f7f67d077504f640d86dc".parseId
const Id656f7f67d077504f640d86dd* = "656f7f67d077504f640d86dd".parseId
const Id656f7f67d077504f640d86de* = "656f7f67d077504f640d86de".parseId
const Id656f7f67d077504f640d86df* = "656f7f67d077504f640d86df".parseId
const Id656f7f67d077504f640d86e0* = "656f7f67d077504f640d86e0".parseId
const Id656f7f67d077504f640d86e1* = "656f7f67d077504f640d86e1".parseId
const Id656f7f67d077504f640d86e2* = "656f7f67d077504f640d86e2".parseId
const Id656f7f67d077504f640d86e3* = "656f7f67d077504f640d86e3".parseId
const Id656f7f67d077504f640d86e4* = "656f7f67d077504f640d86e4".parseId
const Id656f7f67d077504f640d86e5* = "656f7f67d077504f640d86e5".parseId
const Id656f7f67d077504f640d86e6* = "656f7f67d077504f640d86e6".parseId
const Id656f7f67d077504f640d86e7* = "656f7f67d077504f640d86e7".parseId
const Id656f7f67d077504f640d86e8* = "656f7f67d077504f640d86e8".parseId
const Id656f7f67d077504f640d86e9* = "656f7f67d077504f640d86e9".parseId
const Id656f7f67d077504f640d86ea* = "656f7f67d077504f640d86ea".parseId
const Id656f7f67d077504f640d86eb* = "656f7f67d077504f640d86eb".parseId
const Id656f7f67d077504f640d86ec* = "656f7f67d077504f640d86ec".parseId
const Id656f7f67d077504f640d86ed* = "656f7f67d077504f640d86ed".parseId
const Id656f7f67d077504f640d86ee* = "656f7f67d077504f640d86ee".parseId
const Id656f7f67d077504f640d86ef* = "656f7f67d077504f640d86ef".parseId
const Id656f7f67d077504f640d86f0* = "656f7f67d077504f640d86f0".parseId
const Id656f7f67d077504f640d86f1* = "656f7f67d077504f640d86f1".parseId
const Id656f7f67d077504f640d86f2* = "656f7f67d077504f640d86f2".parseId
const Id656f7f67d077504f640d86f3* = "656f7f67d077504f640d86f3".parseId
const Id656f7f67d077504f640d86f4* = "656f7f67d077504f640d86f4".parseId
const Id656f7f67d077504f640d86f5* = "656f7f67d077504f640d86f5".parseId
const Id656f7f67d077504f640d86f6* = "656f7f67d077504f640d86f6".parseId
const Id656f7f67d077504f640d86f7* = "656f7f67d077504f640d86f7".parseId
const Id656f7f67d077504f640d86f8* = "656f7f67d077504f640d86f8".parseId
const Id656f7f67d077504f640d86f9* = "656f7f67d077504f640d86f9".parseId
const Id656f7f67d077504f640d86fa* = "656f7f67d077504f640d86fa".parseId
const Id656f7f67d077504f640d86fb* = "656f7f67d077504f640d86fb".parseId
const Id656f7f67d077504f640d86fc* = "656f7f67d077504f640d86fc".parseId
const Id656f7f67d077504f640d86fd* = "656f7f67d077504f640d86fd".parseId
const Id656f7f67d077504f640d86fe* = "656f7f67d077504f640d86fe".parseId
const Id656f7f67d077504f640d86ff* = "656f7f67d077504f640d86ff".parseId
const Id656f7f67d077504f640d8700* = "656f7f67d077504f640d8700".parseId
const Id656f7f67d077504f640d8701* = "656f7f67d077504f640d8701".parseId
const Id656f7f67d077504f640d8702* = "656f7f67d077504f640d8702".parseId
const Id656f7f67d077504f640d8703* = "656f7f67d077504f640d8703".parseId
const Id656f7f67d077504f640d8704* = "656f7f67d077504f640d8704".parseId
const Id656f7f67d077504f640d8705* = "656f7f67d077504f640d8705".parseId
const Id656f7f67d077504f640d8706* = "656f7f67d077504f640d8706".parseId
const Id656f7f67d077504f640d8707* = "656f7f67d077504f640d8707".parseId
const Id656f7f67d077504f640d8708* = "656f7f67d077504f640d8708".parseId
const Id656f7f67d077504f640d8709* = "656f7f67d077504f640d8709".parseId
const Id656f7f67d077504f640d870a* = "656f7f67d077504f640d870a".parseId
const Id656f7f67d077504f640d870b* = "656f7f67d077504f640d870b".parseId
const Id656f7f67d077504f640d870c* = "656f7f67d077504f640d870c".parseId
const Id656f7f67d077504f640d870d* = "656f7f67d077504f640d870d".parseId
const Id656f7f67d077504f640d870e* = "656f7f67d077504f640d870e".parseId
const Id656f7f67d077504f640d870f* = "656f7f67d077504f640d870f".parseId
const Id656f7f67d077504f640d8710* = "656f7f67d077504f640d8710".parseId
const Id656f7f67d077504f640d8711* = "656f7f67d077504f640d8711".parseId
const Id656f7f67d077504f640d8712* = "656f7f67d077504f640d8712".parseId

# import strformat
# for i in 0..100:
#   let id = newId()
#   echo &"let Id{id}* = \"{id}\".parseId"