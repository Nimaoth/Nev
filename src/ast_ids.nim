import id, ast/model

let IdPrint* = "62e53396564d29f7729344f7".parseId.ClassId
let IdAdd* = "62e53396564d29f7729344f8".parseId.ClassId
let IdSub* = "62e53396564d29f7729344f9".parseId.ClassId
let IdMul* = "62e53396564d29f7729344fa".parseId.ClassId
let IdDiv* = "62e53397564d29f7729344fb".parseId.ClassId
let IdMod* = "62e53397564d29f7729344fc".parseId.ClassId
let IdNegate* = "62e53397564d29f7729344fd".parseId.ClassId
let IdNot* = "62e53397564d29f7729344fe".parseId.ClassId
let IdDeref* = "62e53397564d29f7729344ff".parseId.ClassId
let IdAppendString* = "62e53397564d29f772934500".parseId.ClassId
let IdInt* = "62e53397564d29f772934501".parseId.ClassId
let IdString* = "62e53397564d29f772934502".parseId.ClassId
let IdVoid* = "62e53397564d29f772934503".parseId.ClassId
let IdLess* = "62e53398564d29f772934504".parseId.ClassId
let IdLessEqual* = "62e53398564d29f772934505".parseId.ClassId
let IdGreater* = "62e53398564d29f772934506".parseId.ClassId
let IdGreaterEqual* = "62e53398564d29f772934507".parseId.ClassId
let IdEqual* = "62e53398564d29f772934508".parseId.ClassId
let IdNotEqual* = "62e53398564d29f772934509".parseId.ClassId
let IdAnd* = "62e53398564d29f77293450a".parseId.ClassId
let IdOr* = "62e53398564d29f77293450b".parseId.ClassId
let IdOrder* = "62e53398564d29f77293450c".parseId.ClassId
let IdBuildString* = "62e53399564d29f77293450d".parseId.ClassId

let IdType* = "62e53399564d29f77293450f".parseId.ClassId

let IdBaseLanguage* = "62e53399564d29f77293450e".parseId.LanguageId
let IdFunctionType* = "62e5339a564d29f77293451c".parseId.ClassId
let IdFunctionTypeReturnType* = "62e53399564d29f772934510".parseId.RoleId
let IdFunctionTypeParameterTypes* = "62e53399564d29f772934511".parseId.RoleId

let IdPrintArguments* = "62e5339a564d29f772934518".parseId.RoleId
let IdBuildArguments* = "62e5339a564d29f772934519".parseId.RoleId

let IdUnaryExpression* = "62e5339a564d29f77293451a".parseId.ClassId
let IdUnaryExpressionChild* = "62e5339a564d29f77293451b".parseId.RoleId

let IdIDeclaration* = "62e5339a564d29f77293451d".parseId.ClassId

let IdBreakExpression* = "62e5339b564d29f772934520".parseId.ClassId
let IdContinueExpression* = "62e5339b564d29f772934521".parseId.ClassId
let IdReturnExpression* = "62e5339b564d29f772934522".parseId.ClassId
let Id62e5339b564d29f772934523* = "62e5339b564d29f772934523".parseId.ClassId
let Id62e5339b564d29f772934524* = "62e5339b564d29f772934524".parseId.ClassId
let Id62e5339b564d29f772934525* = "62e5339b564d29f772934525".parseId.ClassId

let IdEmptyLine* = "62e5339b564d29f772934526".parseId.ClassId

let IdBlockChildren* = "62e5339b564d29f772934527".parseId.RoleId
let IdBlock* = "62e5339b564d29f772934528".parseId.ClassId

let IdINamedName* = "62e5339c564d29f772934529".parseId.RoleId
let IdINamed* = "62e5339c564d29f77293452a".parseId.ClassId

let IdAssignmentValue* = "62e5339c564d29f77293452b".parseId.RoleId
let IdAssignmentTarget* = "62e5339c564d29f77293452c".parseId.RoleId
let IdAssignment* = "62e5339c564d29f77293452d".parseId.ClassId

let IdFunctionDefinitionBody* = "62e5339c564d29f77293452e".parseId.RoleId
let IdFunctionDefinitionReturnType* = "62e5339c564d29f77293452f".parseId.RoleId
let IdFunctionDefinitionParameters* = "62e5339c564d29f772934530".parseId.RoleId
let IdFunctionDefinition* = "62e5339c564d29f772934531".parseId.ClassId

let IdParameterDeclValue* = "62e5339d564d29f772934532".parseId.RoleId
let IdParameterDeclType* = "62e5339d564d29f772934533".parseId.RoleId
let IdParameterDecl* = "62e5339d564d29f772934535".parseId.ClassId

let IdWhileExpressionBody* = "62e5339d564d29f772934536".parseId.RoleId
let IdWhileExpressionCondition* = "62e5339d564d29f772934537".parseId.RoleId
let IdWhileExpression* = "62e5339d564d29f772934538".parseId.ClassId

let IdIfExpressionElseCase* = "62e5339d564d29f772934539".parseId.RoleId
let IdIfExpressionThenCase* = "62e5339d564d29f77293453a".parseId.RoleId
let IdThenCase* = "62e5339a564d29f77293451f".parseId.ClassId
let IdThenCaseCondition* = "62e5339e564d29f77293453b".parseId.RoleId
let IdThenCaseBody* = "62e5339a564d29f77293451e".parseId.RoleId
let IdIfExpression* = "62e5339e564d29f77293453c".parseId.ClassId

let IdCallArguments* = "62e5339e564d29f77293453d".parseId.RoleId
let IdCallFunction* = "62e5339e564d29f77293453e".parseId.RoleId
let IdCall* = "62e5339e564d29f77293453f".parseId.ClassId

let IdNodeListChildren* = "62e5339e564d29f772934540".parseId.RoleId
let IdNodeList* = "62e5339e564d29f772934541".parseId.ClassId

let IdVarDeclValue* = "62e5339e564d29f772934542".parseId.RoleId
let IdVarDeclType* = "62e5339e564d29f772934543".parseId.RoleId
let IdVarDecl* = "62e5339f564d29f772934545".parseId.ClassId

let IdLetDeclValue* = "62e5339f564d29f772934546".parseId.RoleId
let IdLetDeclType* = "62e5339f564d29f772934547".parseId.RoleId
let IdLetDecl* = "62e5339f564d29f772934549".parseId.ClassId

let IdConstDeclValue* = "62e5339f564d29f77293454a".parseId.RoleId
let IdConstDeclType* = "62e5339f564d29f77293454b".parseId.RoleId
let IdConstDecl* = "62e5339f564d29f77293454d".parseId.ClassId

let IdEmpty* = "62e533a0564d29f77293454e".parseId.ClassId

let IdNodeReferenceTarget* = "62e533a0564d29f77293454f".parseId.RoleId
let IdNodeReference* = "62e533a0564d29f772934550".parseId.ClassId

let IdBinaryExpressionLeft* = "62e533a0564d29f772934551".parseId.RoleId
let IdBinaryExpressionRight* = "62e533a0564d29f772934552".parseId.RoleId
let IdBinaryExpression* = "62e533a0564d29f772934553".parseId.ClassId

let IdExpression* = "62e533a0564d29f772934554".parseId.ClassId

let IdBoolLiteralValue* = "62e533a0564d29f772934555".parseId.RoleId
let IdBoolLiteral* = "62e533a0564d29f772934556".parseId.ClassId

let IdStringLiteralValue* = "62e533a1564d29f772934557".parseId.RoleId
let IdStringLiteral* = "62e533a1564d29f772934558".parseId.ClassId

let IdIntegerLiteralValue* = "62e533a1564d29f772934559".parseId.RoleId
let IdIntegerLiteral* = "62e533a1564d29f77293455a".parseId.ClassId

let IdStructDefinition* = "654fbb281446e19b38225201".parseId.ClassId
let IdStructDefinitionMembers* = "654fbb281446e19b38225202".parseId.RoleId

let IdStructMemberDefinition* = "654fbb281446e19b38225203".parseId.ClassId
let IdStructMemberDefinitionType* = "654fbb281446e19b38225205".parseId.RoleId
let IdStructMemberDefinitionValue* = "654fbb281446e19b38225206".parseId.RoleId

let IdStructType* = "654fbb281446e19b38225204".parseId.ClassId
let IdStructTypeMemberTypes* = "654fbb281446e19b38225207".parseId.RoleId

let IdStructMemberAccess* = "654fbb281446e19b3822520a".parseId.ClassId
let IdStructMemberAccessMember* = "654fbb281446e19b38225208".parseId.RoleId
let IdStructMemberAccessValue* = "654fbb281446e19b38225209".parseId.RoleId

# new ids

let Id654fbb281446e19b3822520b* = "654fbb281446e19b3822520b".parseId
let Id654fbb281446e19b3822520c* = "654fbb281446e19b3822520c".parseId
let Id654fbb281446e19b3822520d* = "654fbb281446e19b3822520d".parseId
let Id654fbb281446e19b3822520e* = "654fbb281446e19b3822520e".parseId
let Id654fbb281446e19b3822520f* = "654fbb281446e19b3822520f".parseId
let Id654fbb281446e19b38225210* = "654fbb281446e19b38225210".parseId
let Id654fbb281446e19b38225211* = "654fbb281446e19b38225211".parseId
let Id654fbb281446e19b38225212* = "654fbb281446e19b38225212".parseId
let Id654fbb281446e19b38225213* = "654fbb281446e19b38225213".parseId
let Id654fbb281446e19b38225214* = "654fbb281446e19b38225214".parseId
let Id654fbb281446e19b38225215* = "654fbb281446e19b38225215".parseId
let Id654fbb281446e19b38225216* = "654fbb281446e19b38225216".parseId
let Id654fbb281446e19b38225217* = "654fbb281446e19b38225217".parseId
let Id654fbb281446e19b38225218* = "654fbb281446e19b38225218".parseId
let Id654fbb281446e19b38225219* = "654fbb281446e19b38225219".parseId
let Id654fbb281446e19b3822521a* = "654fbb281446e19b3822521a".parseId
let Id654fbb281446e19b3822521b* = "654fbb281446e19b3822521b".parseId
let Id654fbb281446e19b3822521c* = "654fbb281446e19b3822521c".parseId
let Id654fbb281446e19b3822521d* = "654fbb281446e19b3822521d".parseId
let Id654fbb281446e19b3822521e* = "654fbb281446e19b3822521e".parseId
let Id654fbb281446e19b3822521f* = "654fbb281446e19b3822521f".parseId
let Id654fbb281446e19b38225220* = "654fbb281446e19b38225220".parseId
let Id654fbb281446e19b38225221* = "654fbb281446e19b38225221".parseId
let Id654fbb281446e19b38225222* = "654fbb281446e19b38225222".parseId
let Id654fbb281446e19b38225223* = "654fbb281446e19b38225223".parseId
let Id654fbb281446e19b38225224* = "654fbb281446e19b38225224".parseId
let Id654fbb281446e19b38225225* = "654fbb281446e19b38225225".parseId
let Id654fbb281446e19b38225226* = "654fbb281446e19b38225226".parseId
let Id654fbb281446e19b38225227* = "654fbb281446e19b38225227".parseId
let Id654fbb281446e19b38225228* = "654fbb281446e19b38225228".parseId
let Id654fbb281446e19b38225229* = "654fbb281446e19b38225229".parseId
let Id654fbb281446e19b3822522a* = "654fbb281446e19b3822522a".parseId
let Id654fbb281446e19b3822522b* = "654fbb281446e19b3822522b".parseId
let Id654fbb281446e19b3822522c* = "654fbb281446e19b3822522c".parseId
let Id654fbb281446e19b3822522d* = "654fbb281446e19b3822522d".parseId
let Id654fbb281446e19b3822522e* = "654fbb281446e19b3822522e".parseId
let Id654fbb281446e19b3822522f* = "654fbb281446e19b3822522f".parseId
let Id654fbb281446e19b38225230* = "654fbb281446e19b38225230".parseId
let Id654fbb281446e19b38225231* = "654fbb281446e19b38225231".parseId
let Id654fbb281446e19b38225232* = "654fbb281446e19b38225232".parseId
let Id654fbb281446e19b38225233* = "654fbb281446e19b38225233".parseId
let Id654fbb281446e19b38225234* = "654fbb281446e19b38225234".parseId
let Id654fbb281446e19b38225235* = "654fbb281446e19b38225235".parseId
let Id654fbb281446e19b38225236* = "654fbb281446e19b38225236".parseId
let Id654fbb281446e19b38225237* = "654fbb281446e19b38225237".parseId
let Id654fbb281446e19b38225238* = "654fbb281446e19b38225238".parseId
let Id654fbb281446e19b38225239* = "654fbb281446e19b38225239".parseId
let Id654fbb281446e19b3822523a* = "654fbb281446e19b3822523a".parseId
let Id654fbb281446e19b3822523b* = "654fbb281446e19b3822523b".parseId
let Id654fbb281446e19b3822523c* = "654fbb281446e19b3822523c".parseId
let Id654fbb281446e19b3822523d* = "654fbb281446e19b3822523d".parseId
let Id654fbb281446e19b3822523e* = "654fbb281446e19b3822523e".parseId
let Id654fbb281446e19b3822523f* = "654fbb281446e19b3822523f".parseId
let Id654fbb281446e19b38225240* = "654fbb281446e19b38225240".parseId
let Id654fbb281446e19b38225241* = "654fbb281446e19b38225241".parseId
let Id654fbb281446e19b38225242* = "654fbb281446e19b38225242".parseId
let Id654fbb281446e19b38225243* = "654fbb281446e19b38225243".parseId
let Id654fbb281446e19b38225244* = "654fbb281446e19b38225244".parseId
let Id654fbb281446e19b38225245* = "654fbb281446e19b38225245".parseId
let Id654fbb281446e19b38225246* = "654fbb281446e19b38225246".parseId
let Id654fbb281446e19b38225247* = "654fbb281446e19b38225247".parseId
let Id654fbb281446e19b38225248* = "654fbb281446e19b38225248".parseId
let Id654fbb281446e19b38225249* = "654fbb281446e19b38225249".parseId
let Id654fbb281446e19b3822524a* = "654fbb281446e19b3822524a".parseId
let Id654fbb281446e19b3822524b* = "654fbb281446e19b3822524b".parseId
let Id654fbb281446e19b3822524c* = "654fbb281446e19b3822524c".parseId
let Id654fbb281446e19b3822524d* = "654fbb281446e19b3822524d".parseId
let Id654fbb281446e19b3822524e* = "654fbb281446e19b3822524e".parseId
let Id654fbb281446e19b3822524f* = "654fbb281446e19b3822524f".parseId
let Id654fbb281446e19b38225250* = "654fbb281446e19b38225250".parseId
let Id654fbb281446e19b38225251* = "654fbb281446e19b38225251".parseId
let Id654fbb281446e19b38225252* = "654fbb281446e19b38225252".parseId
let Id654fbb281446e19b38225253* = "654fbb281446e19b38225253".parseId
let Id654fbb281446e19b38225254* = "654fbb281446e19b38225254".parseId
let Id654fbb281446e19b38225255* = "654fbb281446e19b38225255".parseId
let Id654fbb281446e19b38225256* = "654fbb281446e19b38225256".parseId
let Id654fbb281446e19b38225257* = "654fbb281446e19b38225257".parseId
let Id654fbb281446e19b38225258* = "654fbb281446e19b38225258".parseId
let Id654fbb281446e19b38225259* = "654fbb281446e19b38225259".parseId
let Id654fbb281446e19b3822525a* = "654fbb281446e19b3822525a".parseId
let Id654fbb281446e19b3822525b* = "654fbb281446e19b3822525b".parseId
let Id654fbb281446e19b3822525c* = "654fbb281446e19b3822525c".parseId
let Id654fbb281446e19b3822525d* = "654fbb281446e19b3822525d".parseId
let Id654fbb281446e19b3822525e* = "654fbb281446e19b3822525e".parseId
let Id654fbb281446e19b3822525f* = "654fbb281446e19b3822525f".parseId
let Id654fbb281446e19b38225260* = "654fbb281446e19b38225260".parseId
let Id654fbb281446e19b38225261* = "654fbb281446e19b38225261".parseId
let Id654fbb281446e19b38225262* = "654fbb281446e19b38225262".parseId
let Id654fbb281446e19b38225263* = "654fbb281446e19b38225263".parseId
let Id654fbb281446e19b38225264* = "654fbb281446e19b38225264".parseId
let Id654fbb281446e19b38225265* = "654fbb281446e19b38225265".parseId

# import strformat
# for i in 0..100:
#   let id = newId()
#   echo &"let Id{id}* = \"{id}\".parseId"