#
#
#           The Nimrod Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements the parser of the standard Nimrod syntax.
# The parser strictly reflects the grammar ("doc/grammar.txt"); however
# it uses several helper routines to keep the parser small. A special
# efficient algorithm is used for the precedence levels. The parser here can
# be seen as a refinement of the grammar, as it specifies how the AST is built
# from the grammar and how comments belong to the AST. 


# In fact the grammar is generated from this file:
when isMainModule:
  import pegs
  var outp = open("compiler/grammar.txt", fmWrite)
  for line in lines("compiler/parser.nim"):
    if line =~ peg" \s* '#| ' {.*}":
      outp.writeln matches[0]
  outp.close

import
  llstream, lexer, idents, strutils, ast, astalgo, msgs

type
  TParser*{.final.} = object  # a TParser object represents a module that
                              # is being parsed
    currInd: int              # current indentation
    firstTok: bool
    lex*: TLexer              # the lexer that is used for parsing
    tok*: TToken              # the current token

proc ParseAll*(p: var TParser): PNode
proc openParser*(p: var TParser, filename: string, inputstream: PLLStream)
proc closeParser*(p: var TParser)
proc parseTopLevelStmt*(p: var TParser): PNode
  # implements an iterator. Returns the next top-level statement or
  # emtyNode if end of stream.

proc parseString*(s: string, filename: string = "", line: int = 0): PNode
  # filename and line could be set optionally, when the string originates 
  # from a certain source file. This way, the compiler could generate
  # correct error messages referring to the original source.
  
# helpers for the other parsers
proc getPrecedence*(tok: TToken): int
proc isOperator*(tok: TToken): bool
proc getTok*(p: var TParser)
proc parMessage*(p: TParser, msg: TMsgKind, arg: string = "")
proc skipComment*(p: var TParser, node: PNode)
proc newNodeP*(kind: TNodeKind, p: TParser): PNode
proc newIntNodeP*(kind: TNodeKind, intVal: BiggestInt, p: TParser): PNode
proc newFloatNodeP*(kind: TNodeKind, floatVal: BiggestFloat, p: TParser): PNode
proc newStrNodeP*(kind: TNodeKind, strVal: string, p: TParser): PNode
proc newIdentNodeP*(ident: PIdent, p: TParser): PNode
proc expectIdentOrKeyw*(p: TParser)
proc ExpectIdent*(p: TParser)
proc parLineInfo*(p: TParser): TLineInfo
proc Eat*(p: var TParser, TokType: TTokType)
proc skipInd*(p: var TParser)
proc optPar*(p: var TParser)
proc optInd*(p: var TParser, n: PNode)
proc indAndComment*(p: var TParser, n: PNode)
proc setBaseFlags*(n: PNode, base: TNumericalBase)
proc parseSymbol*(p: var TParser): PNode
proc parseTry(p: var TParser): PNode
proc parseCase(p: var TParser): PNode
# implementation

proc getTok(p: var TParser) = 
  rawGetTok(p.lex, p.tok)

proc OpenParser*(p: var TParser, fileIdx: int32, inputStream: PLLStream) =
  initToken(p.tok)
  OpenLexer(p.lex, fileIdx, inputstream)
  getTok(p)                   # read the first token
  p.firstTok = true

proc OpenParser*(p: var TParser, filename: string, inputStream: PLLStream) =
  openParser(p, filename.fileInfoIdx, inputStream)

proc CloseParser(p: var TParser) = 
  CloseLexer(p.lex)

proc parMessage(p: TParser, msg: TMsgKind, arg: string = "") = 
  lexMessage(p.lex, msg, arg)

proc parMessage(p: TParser, msg: TMsgKind, tok: TToken) = 
  lexMessage(p.lex, msg, prettyTok(tok))

template withInd(p: expr, body: stmt) {.immediate.} =
  let oldInd = p.currInd
  p.currInd = p.tok.indent
  body
  p.currInd = oldInd

template realInd(p): bool = p.tok.indent > p.currInd
template sameInd(p): bool = p.tok.indent == p.currInd
template sameOrNoInd(p): bool = p.tok.indent == p.currInd or p.tok.indent < 0

proc rawSkipComment(p: var TParser, node: PNode) =
  if p.tok.tokType == tkComment:
    if node != nil:
      if node.comment == nil: node.comment = ""
      add(node.comment, p.tok.literal)
    else:
      parMessage(p, errInternal, "skipComment")
    getTok(p)

proc skipComment(p: var TParser, node: PNode) =
  if p.tok.indent < 0: rawSkipComment(p, node)

proc skipInd(p: var TParser) =
  if p.tok.indent >= 0:
    if not realInd(p): parMessage(p, errInvalidIndentation)

proc optPar(p: var TParser) =
  if p.tok.indent >= 0:
    if p.tok.indent < p.currInd: parMessage(p, errInvalidIndentation)

proc optInd(p: var TParser, n: PNode) =
  skipComment(p, n)
  skipInd(p)

proc getTokNoInd(p: var TParser) =
  getTok(p)
  if p.tok.indent >= 0: parMessage(p, errInvalidIndentation)

proc expectIdentOrKeyw(p: TParser) =
  if p.tok.tokType != tkSymbol and not isKeyword(p.tok.tokType):
    lexMessage(p.lex, errIdentifierExpected, prettyTok(p.tok))
  
proc ExpectIdent(p: TParser) =
  if p.tok.tokType != tkSymbol:
    lexMessage(p.lex, errIdentifierExpected, prettyTok(p.tok))
  
proc Eat(p: var TParser, TokType: TTokType) =
  if p.tok.TokType == TokType: getTok(p)
  else: lexMessage(p.lex, errTokenExpected, TokTypeToStr[tokType])
  
proc parLineInfo(p: TParser): TLineInfo =
  result = getLineInfo(p.lex, p.tok)

proc indAndComment(p: var TParser, n: PNode) =
  if p.tok.indent > p.currInd:
    if p.tok.tokType == tkComment: rawSkipComment(p, n)
    else: parMessage(p, errInvalidIndentation)
  else:
    skipComment(p, n)
  
proc newNodeP(kind: TNodeKind, p: TParser): PNode = 
  result = newNodeI(kind, parLineInfo(p))

proc newIntNodeP(kind: TNodeKind, intVal: BiggestInt, p: TParser): PNode = 
  result = newNodeP(kind, p)
  result.intVal = intVal

proc newFloatNodeP(kind: TNodeKind, floatVal: BiggestFloat, 
                   p: TParser): PNode =
  result = newNodeP(kind, p)
  result.floatVal = floatVal

proc newStrNodeP(kind: TNodeKind, strVal: string, p: TParser): PNode = 
  result = newNodeP(kind, p)
  result.strVal = strVal

proc newIdentNodeP(ident: PIdent, p: TParser): PNode = 
  result = newNodeP(nkIdent, p)
  result.ident = ident

proc parseExpr(p: var TParser): PNode
proc parseStmt(p: var TParser): PNode
proc parseTypeDesc(p: var TParser): PNode
proc parseDoBlocks(p: var TParser, call: PNode)
proc parseParamList(p: var TParser, retColon = true): PNode

proc relevantOprChar(ident: PIdent): char {.inline.} =
  result = ident.s[0]
  var L = ident.s.len
  if result == '\\' and L > 1:
    result = ident.s[1]

proc IsSigilLike(tok: TToken): bool {.inline.} =
  result = tok.tokType == tkOpr and relevantOprChar(tok.ident) == '@'

proc IsLeftAssociative(tok: TToken): bool {.inline.} =
  result = tok.tokType != tkOpr or relevantOprChar(tok.ident) != '^'

proc getPrecedence(tok: TToken): int = 
  case tok.tokType
  of tkOpr:
    let L = tok.ident.s.len
    let relevantChar = relevantOprChar(tok.ident)
    
    template considerAsgn(value: expr) = 
      result = if tok.ident.s[L-1] == '=': 1 else: value     
    
    case relevantChar
    of '$', '^': considerAsgn(10)
    of '*', '%', '/', '\\': considerAsgn(9)
    of '~': result = 8
    of '+', '-', '|': considerAsgn(8)
    of '&': considerAsgn(7)
    of '=', '<', '>', '!': result = 5
    of '.': considerAsgn(6)
    of '?': result = 2
    else: considerAsgn(2)
  of tkDiv, tkMod, tkShl, tkShr: result = 9
  of tkIn, tkNotIn, tkIs, tkIsNot, tkNot, tkOf, tkAs: result = 5
  of tkDotDot: result = 6
  of tkAnd: result = 4
  of tkOr, tkXor: result = 3
  else: result = - 10
  
proc isOperator(tok: TToken): bool = 
  result = getPrecedence(tok) >= 0

#| module = stmt ^* (';' / IND{=})
#|
#| comma = ',' COMMENT?
#| semicolon = ';' COMMENT?
#| colon = ':' COMMENT?
#| colcom = ':' COMMENT?
#| 
#| operator =  OP0 | OP1 | OP2 | OP3 | OP4 | OP5 | OP6 | OP7 | OP8 | OP9
#|          | 'or' | 'xor' | 'and'
#|          | 'is' | 'isnot' | 'in' | 'notin' | 'of'
#|          | 'div' | 'mod' | 'shl' | 'shr' | 'not' | 'addr' | 'static' | '..'
#| 
#| prefixOperator = operator
#| 
#| optInd = COMMENT?
#| optPar = (IND{>} | IND{=})?
#| 
#| simpleExpr = assignExpr (OP0 optInd assignExpr)*
#| assignExpr = orExpr (OP1 optInd orExpr)*
#| orExpr = andExpr (OP2 optInd andExpr)*
#| andExpr = cmpExpr (OP3 optInd cmpExpr)*
#| cmpExpr = sliceExpr (OP4 optInd sliceExpr)*
#| sliceExpr = ampExpr (OP5 optInd ampExpr)*
#| ampExpr = plusExpr (OP6 optInd plusExpr)*
#| plusExpr = mulExpr (OP7 optInd mulExpr)*
#| mulExpr = dollarExpr (OP8 optInd dollarExpr)*
#| dollarExpr = primary (OP9 optInd primary)*

proc colcom(p: var TParser, n: PNode) =
  eat(p, tkColon)
  skipComment(p, n)

proc parseSymbol(p: var TParser): PNode =
  #| symbol = '`' (KEYW|IDENT|operator|'(' ')'|'[' ']'|'{' '}'|'='|literal)+ '`'
  #|        | IDENT
  case p.tok.tokType
  of tkSymbol: 
    result = newIdentNodeP(p.tok.ident, p)
    getTok(p)
  of tkAccent: 
    result = newNodeP(nkAccQuoted, p)
    getTok(p)
    while true:
      case p.tok.tokType
      of tkBracketLe: 
        add(result, newIdentNodeP(getIdent"[]", p))
        getTok(p)
        eat(p, tkBracketRi)
      of tkEquals:
        add(result, newIdentNodeP(getIdent"=", p))
        getTok(p)
      of tkParLe:
        add(result, newIdentNodeP(getIdent"()", p))
        getTok(p)
        eat(p, tkParRi)
      of tkCurlyLe:
        add(result, newIdentNodeP(getIdent"{}", p))
        getTok(p)
        eat(p, tkCurlyRi)
      of tokKeywordLow..tokKeywordHigh, tkSymbol, tkOpr, tkDotDot:
        add(result, newIdentNodeP(p.tok.ident, p))
        getTok(p)
      of tkIntLit..tkCharLit:
        add(result, newIdentNodeP(getIdent(tokToStr(p.tok)), p))
        getTok(p)
      else:
        if result.len == 0: 
          parMessage(p, errIdentifierExpected, p.tok)
        break
    eat(p, tkAccent)
  else:
    parMessage(p, errIdentifierExpected, p.tok)
    getTok(p) # BUGFIX: We must consume a token here to prevent endless loops!
    result = ast.emptyNode

proc indexExpr(p: var TParser): PNode = 
  #| indexExpr = expr
  result = parseExpr(p)

proc indexExprList(p: var TParser, first: PNode, k: TNodeKind, 
                   endToken: TTokType): PNode = 
  #| indexExprList = indexExpr ^+ comma
  result = newNodeP(k, p)
  addSon(result, first)
  getTok(p)
  optInd(p, result)
  while p.tok.tokType notin {endToken, tkEof}:
    var a = indexExpr(p)
    addSon(result, a)
    if p.tok.tokType != tkComma: break 
    getTok(p)
    skipComment(p, a)
  optPar(p)
  eat(p, endToken)

proc colonOrEquals(p: var TParser, a: PNode): PNode =
  if p.tok.tokType == tkColon:
    result = newNodeP(nkExprColonExpr, p)
    getTok(p)
    #optInd(p, result)
    addSon(result, a)
    addSon(result, parseExpr(p))
  elif p.tok.tokType == tkEquals:
    result = newNodeP(nkExprEqExpr, p)
    getTok(p)
    #optInd(p, result)
    addSon(result, a)
    addSon(result, parseExpr(p))
  else:
    result = a

proc exprColonEqExpr(p: var TParser): PNode =
  #| exprColonEqExpr = expr (':'|'=' expr)?
  var a = parseExpr(p)
  result = colonOrEquals(p, a)

proc exprList(p: var TParser, endTok: TTokType, result: PNode) = 
  #| exprList = expr ^+ comma
  getTok(p)
  optInd(p, result)
  while (p.tok.tokType != endTok) and (p.tok.tokType != tkEof): 
    var a = parseExpr(p)
    addSon(result, a)
    if p.tok.tokType != tkComma: break 
    getTok(p)
    optInd(p, a)
  eat(p, endTok)

proc dotExpr(p: var TParser, a: PNode): PNode =
  #| dotExpr = expr '.' optInd ('type' | 'addr' | symbol)
  var info = p.parLineInfo
  getTok(p)
  optInd(p, a)
  case p.tok.tokType
  of tkType:
    result = newNodeP(nkTypeOfExpr, p)
    getTok(p)
    addSon(result, a)
  of tkAddr:
    result = newNodeP(nkAddr, p)
    getTok(p)
    addSon(result, a)
  else:
    result = newNodeI(nkDotExpr, info)
    addSon(result, a)
    addSon(result, parseSymbol(p))

proc qualifiedIdent(p: var TParser): PNode = 
  #| qualifiedIdent = symbol ('.' optInd ('type' | 'addr' | symbol))?
  result = parseSymbol(p)
  if p.tok.tokType == tkDot: result = dotExpr(p, result)

proc exprColonEqExprListAux(p: var TParser, endTok: TTokType, result: PNode) =
  assert(endTok in {tkCurlyRi, tkCurlyDotRi, tkBracketRi, tkParRi})
  getTok(p)
  optInd(p, result)
  while p.tok.tokType != endTok and p.tok.tokType != tkEof:
    var a = exprColonEqExpr(p)
    addSon(result, a)
    if p.tok.tokType != tkComma: break 
    getTok(p)
    skipComment(p, a)
  optPar(p)
  eat(p, endTok)

proc exprColonEqExprList(p: var TParser, kind: TNodeKind,
                         endTok: TTokType): PNode =
  #| exprColonEqExprList = exprColonEqExpr (comma exprColonEqExpr)* (comma)?
  result = newNodeP(kind, p)
  exprColonEqExprListAux(p, endTok, result)

proc setOrTableConstr(p: var TParser): PNode =
  #| setOrTableConstr = '{' ((exprColonEqExpr comma)* | ':' ) '}'
  result = newNodeP(nkCurly, p)
  getTok(p) # skip '{'
  optInd(p, result)
  if p.tok.tokType == tkColon:
    getTok(p) # skip ':'
    result.kind = nkTableConstr
  else:
    while p.tok.tokType notin {tkCurlyRi, tkEof}:
      var a = exprColonEqExpr(p)
      if a.kind == nkExprColonExpr: result.kind = nkTableConstr
      addSon(result, a)
      if p.tok.tokType != tkComma: break 
      getTok(p)
      skipComment(p, a)
  optPar(p)
  eat(p, tkCurlyRi) # skip '}'

proc parseCast(p: var TParser): PNode = 
  #| castExpr = 'cast' '[' optInd typeDesc optPar ']' '(' optInd expr optPar ')'
  result = newNodeP(nkCast, p)
  getTok(p)
  eat(p, tkBracketLe)
  optInd(p, result)
  addSon(result, parseTypeDesc(p))
  optPar(p)
  eat(p, tkBracketRi)
  eat(p, tkParLe)
  optInd(p, result)
  addSon(result, parseExpr(p))
  optPar(p)
  eat(p, tkParRi)

proc setBaseFlags(n: PNode, base: TNumericalBase) = 
  case base
  of base10: nil
  of base2: incl(n.flags, nfBase2)
  of base8: incl(n.flags, nfBase8)
  of base16: incl(n.flags, nfBase16)
  
proc parseGStrLit(p: var TParser, a: PNode): PNode = 
  case p.tok.tokType
  of tkGStrLit: 
    result = newNodeP(nkCallStrLit, p)
    addSon(result, a)
    addSon(result, newStrNodeP(nkRStrLit, p.tok.literal, p))
    getTok(p)
  of tkGTripleStrLit: 
    result = newNodeP(nkCallStrLit, p)
    addSon(result, a)
    addSon(result, newStrNodeP(nkTripleStrLit, p.tok.literal, p))
    getTok(p)
  else:
    result = a

type
  TPrimaryMode = enum pmNormal, pmTypeDesc, pmTypeDef, pmSkipSuffix

proc complexOrSimpleStmt(p: var TParser): PNode
proc simpleExpr(p: var TParser, mode = pmNormal): PNode

proc semiStmtList(p: var TParser, result: PNode) =
  result.add(complexOrSimpleStmt(p))
  while p.tok.tokType == tkSemicolon:
    getTok(p)
    optInd(p, result)
    result.add(complexOrSimpleStmt(p))
  result.kind = nkStmtListExpr

proc parsePar(p: var TParser): PNode =
  #| parKeyw = 'discard' | 'include' | 'if' | 'while' | 'case' | 'try'
  #|         | 'finally' | 'except' | 'for' | 'block' | 'const' | 'let'
  #|         | 'when' | 'var' | 'mixin'
  #| par = '(' optInd (&parKeyw complexOrSimpleStmt ^+ ';' 
  #|                  | simpleExpr ('=' expr (';' complexOrSimpleStmt ^+ ';' )? )?
  #|                             | (':' expr)? (',' (exprColonEqExpr comma?)*)?  )?
  #|         optPar ')'
  #
  # unfortunately it's ambiguous: (expr: expr) vs (exprStmt); however a 
  # leading ';' could be used to enforce a 'stmt' context ...
  result = newNodeP(nkPar, p)
  getTok(p)
  optInd(p, result)
  if p.tok.tokType in {tkDiscard, tkInclude, tkIf, tkWhile, tkCase, 
                       tkTry, tkFinally, tkExcept, tkFor, tkBlock, 
                       tkConst, tkLet, tkWhen, tkVar,
                       tkMixin}:
    # XXX 'bind' used to be an expression, so we exclude it here;
    # tests/reject/tbind2 fails otherwise.
    semiStmtList(p, result)
  elif p.tok.tokType == tkSemicolon:
    # '(;' enforces 'stmt' context:
    getTok(p)
    optInd(p, result)
    semiStmtList(p, result)
  elif p.tok.tokType != tkParRi:
    var a = simpleExpr(p)
    if p.tok.tokType == tkEquals:
      # special case: allow assignments
      getTok(p)
      optInd(p, result)
      let b = parseExpr(p)
      let asgn = newNodeI(nkAsgn, a.info, 2)
      asgn.sons[0] = a
      asgn.sons[1] = b
      result.add(asgn)
    elif p.tok.tokType == tkSemicolon:
      # stmt context:
      result.add(a)
      semiStmtList(p, result)
    else:
      a = colonOrEquals(p, a)
      result.add(a)
      if p.tok.tokType == tkComma:
        getTok(p)
        skipComment(p, a)
        while p.tok.tokType != tkParRi and p.tok.tokType != tkEof:
          var a = exprColonEqExpr(p)
          addSon(result, a)
          if p.tok.tokType != tkComma: break 
          getTok(p)
          skipComment(p, a)
  optPar(p)
  eat(p, tkParRi)

proc identOrLiteral(p: var TParser, mode: TPrimaryMode): PNode = 
  #| generalizedLit = GENERALIZED_STR_LIT | GENERALIZED_TRIPLESTR_LIT
  #| identOrLiteral = generalizedLit | symbol 
  #|                | INT_LIT | INT8_LIT | INT16_LIT | INT32_LIT | INT64_LIT
  #|                | UINT_LIT | UINT8_LIT | UINT16_LIT | UINT32_LIT | UINT64_LIT
  #|                | FLOAT_LIT | FLOAT32_LIT | FLOAT64_LIT
  #|                | STR_LIT | RSTR_LIT | TRIPLESTR_LIT
  #|                | CHAR_LIT
  #|                | NIL
  #|                | par | arrayConstr | setOrTableConstr
  #|                | castExpr
  #| tupleConstr = '(' optInd (exprColonEqExpr comma?)* optPar ')'
  #| arrayConstr = '[' optInd (exprColonEqExpr comma?)* optPar ']'
  case p.tok.tokType
  of tkSymbol:
    result = newIdentNodeP(p.tok.ident, p)
    getTok(p)
    result = parseGStrLit(p, result)
  of tkAccent: 
    result = parseSymbol(p)       # literals
  of tkIntLit:
    result = newIntNodeP(nkIntLit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkInt8Lit: 
    result = newIntNodeP(nkInt8Lit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkInt16Lit: 
    result = newIntNodeP(nkInt16Lit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkInt32Lit: 
    result = newIntNodeP(nkInt32Lit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkInt64Lit: 
    result = newIntNodeP(nkInt64Lit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkUIntLit: 
    result = newIntNodeP(nkUIntLit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkUInt8Lit: 
    result = newIntNodeP(nkUInt8Lit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkUInt16Lit: 
    result = newIntNodeP(nkUInt16Lit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkUInt32Lit: 
    result = newIntNodeP(nkUInt32Lit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkUInt64Lit: 
    result = newIntNodeP(nkUInt64Lit, p.tok.iNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkFloatLit: 
    result = newFloatNodeP(nkFloatLit, p.tok.fNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkFloat32Lit: 
    result = newFloatNodeP(nkFloat32Lit, p.tok.fNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkFloat64Lit: 
    result = newFloatNodeP(nkFloat64Lit, p.tok.fNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkFloat128Lit:
    result = newFloatNodeP(nkFloat128Lit, p.tok.fNumber, p)
    setBaseFlags(result, p.tok.base)
    getTok(p)
  of tkStrLit: 
    result = newStrNodeP(nkStrLit, p.tok.literal, p)
    getTok(p)
  of tkRStrLit: 
    result = newStrNodeP(nkRStrLit, p.tok.literal, p)
    getTok(p)
  of tkTripleStrLit: 
    result = newStrNodeP(nkTripleStrLit, p.tok.literal, p)
    getTok(p)
  of tkCharLit: 
    result = newIntNodeP(nkCharLit, ord(p.tok.literal[0]), p)
    getTok(p)
  of tkNil: 
    result = newNodeP(nkNilLit, p)
    getTok(p)
  of tkParLe:
    # () constructor
    if mode in {pmTypeDesc, pmTypeDef}:
      result = exprColonEqExprList(p, nkPar, tkParRi)
    else:
      result = parsePar(p)
  of tkCurlyLe:
    # {} constructor
    result = setOrTableConstr(p)
  of tkBracketLe:
    # [] constructor
    result = exprColonEqExprList(p, nkBracket, tkBracketRi)
  of tkCast: 
    result = parseCast(p)
  else:
    parMessage(p, errExprExpected, p.tok)
    getTok(p)  # we must consume a token here to prevend endless loops!
    result = ast.emptyNode

proc namedParams(p: var TParser, callee: PNode,
                 kind: TNodeKind, endTok: TTokType): PNode =
  let a = callee
  result = newNodeP(kind, p)
  addSon(result, a)
  exprColonEqExprListAux(p, endTok, result)

proc primarySuffix(p: var TParser, r: PNode): PNode =
  #| primarySuffix = '(' (exprColonEqExpr comma?)* ')' doBlocks?
  #|               | doBlocks
  #|               | '.' optInd ('type' | 'addr' | symbol) generalizedLit?
  #|               | '[' optInd indexExprList optPar ']'
  #|               | '{' optInd indexExprList optPar '}'
  result = r
  while p.tok.indent < 0:
    case p.tok.tokType
    of tkParLe:
      result = namedParams(p, result, nkCall, tkParRi)
      if result.len > 1 and result.sons[1].kind == nkExprColonExpr:
        result.kind = nkObjConstr
      else:
        parseDoBlocks(p, result)
    of tkDo:
      var a = result
      result = newNodeP(nkCall, p)
      addSon(result, a)
      parseDoBlocks(p, result)
    of tkDot:
      result = dotExpr(p, result)
      result = parseGStrLit(p, result)
    of tkBracketLe:
      result = namedParams(p, result, nkBracketExpr, tkBracketRi)
    of tkCurlyLe:
      result = namedParams(p, result, nkCurlyExpr, tkCurlyRi)
    else: break

proc primary(p: var TParser, mode: TPrimaryMode): PNode

proc simpleExprAux(p: var TParser, limit: int, mode: TPrimaryMode): PNode =
  result = primary(p, mode)
  # expand while operators have priorities higher than 'limit'
  var opPrec = getPrecedence(p.tok)
  let modeB = if mode == pmTypeDef: pmTypeDesc else: mode
  # the operator itself must not start on a new line:
  while opPrec >= limit and p.tok.indent < 0:
    var leftAssoc = ord(IsLeftAssociative(p.tok))
    var a = newNodeP(nkInfix, p)
    var opNode = newIdentNodeP(p.tok.ident, p) # skip operator:
    getTok(p)
    optInd(p, opNode)
    # read sub-expression with higher priority:
    var b = simpleExprAux(p, opPrec + leftAssoc, modeB)
    addSon(a, opNode)
    addSon(a, result)
    addSon(a, b)
    result = a
    opPrec = getPrecedence(p.tok)
  
proc simpleExpr(p: var TParser, mode = pmNormal): PNode =
  result = simpleExprAux(p, -1, mode)

proc parseIfExpr(p: var TParser, kind: TNodeKind): PNode =
  #| condExpr = expr colcom expr optInd
  #|         ('elif' expr colcom expr optInd)*
  #|          'else' colcom expr
  #| ifExpr = 'if' condExpr
  #| whenExpr = 'when' condExpr
  result = newNodeP(kind, p)
  while true:
    getTok(p)                 # skip `if`, `elif`
    var branch = newNodeP(nkElifExpr, p)
    addSon(branch, parseExpr(p))
    colcom(p, branch)
    addSon(branch, parseExpr(p))
    optInd(p, branch)
    addSon(result, branch)
    if p.tok.tokType != tkElif: break 
  var branch = newNodeP(nkElseExpr, p)
  eat(p, tkElse)
  colcom(p, branch)
  addSon(branch, parseExpr(p))
  addSon(result, branch)

proc parsePragma(p: var TParser): PNode =
  #| pragma = '{.' optInd (exprColonExpr comma?)* optPar ('.}' | '}')
  result = newNodeP(nkPragma, p)
  getTok(p)
  optInd(p, result)
  while p.tok.tokType notin {tkCurlyDotRi, tkCurlyRi, tkEof}:
    var a = exprColonEqExpr(p)
    addSon(result, a)
    if p.tok.tokType == tkComma:
      getTok(p)
      skipComment(p, a)
  optPar(p)
  if p.tok.tokType in {tkCurlyDotRi, tkCurlyRi}: getTok(p)
  else: parMessage(p, errTokenExpected, ".}")
  
proc identVis(p: var TParser): PNode = 
  #| identVis = symbol opr?  # postfix position
  var a = parseSymbol(p)
  if p.tok.tokType == tkOpr: 
    result = newNodeP(nkPostfix, p)
    addSon(result, newIdentNodeP(p.tok.ident, p))
    addSon(result, a)
    getTok(p)
  else: 
    result = a
  
proc identWithPragma(p: var TParser): PNode = 
  #| identWithPragma = identVis pragma?
  var a = identVis(p)
  if p.tok.tokType == tkCurlyDotLe: 
    result = newNodeP(nkPragmaExpr, p)
    addSon(result, a)
    addSon(result, parsePragma(p))
  else: 
    result = a

type
  TDeclaredIdentFlag = enum 
    withPragma,               # identifier may have pragma
    withBothOptional          # both ':' and '=' parts are optional
  TDeclaredIdentFlags = set[TDeclaredIdentFlag]

proc parseIdentColonEquals(p: var TParser, flags: TDeclaredIdentFlags): PNode = 
  #| declColonEquals = identWithPragma (comma identWithPragma)* comma?
  #|                   (':' optInd typeDesc)? ('=' optInd expr)?
  #| identColonEquals = ident (comma ident)* comma?
  #|      (':' optInd typeDesc)? ('=' optInd expr)?)
  var a: PNode
  result = newNodeP(nkIdentDefs, p)
  while true: 
    case p.tok.tokType
    of tkSymbol, tkAccent: 
      if withPragma in flags: a = identWithPragma(p)
      else: a = parseSymbol(p)
      if a.kind == nkEmpty: return 
    else: break 
    addSon(result, a)
    if p.tok.tokType != tkComma: break 
    getTok(p)
    optInd(p, a)
  if p.tok.tokType == tkColon: 
    getTok(p)
    optInd(p, result)
    addSon(result, parseTypeDesc(p))
  else: 
    addSon(result, ast.emptyNode)
    if (p.tok.tokType != tkEquals) and not (withBothOptional in flags): 
      parMessage(p, errColonOrEqualsExpected, p.tok)
  if p.tok.tokType == tkEquals: 
    getTok(p)
    optInd(p, result)
    addSon(result, parseExpr(p))
  else: 
    addSon(result, ast.emptyNode)
  
proc parseTuple(p: var TParser, indentAllowed = false): PNode =
  #| inlTupleDecl = 'tuple'
  #|     [' optInd  (identColonEquals (comma/semicolon)?)*  optPar ']'
  #| extTupleDecl = 'tuple'
  #|     COMMENT? (IND{>} identColonEquals (IND{=} identColonEquals)*)?
  result = newNodeP(nkTupleTy, p)
  getTok(p)
  if p.tok.tokType == tkBracketLe:
    getTok(p)
    optInd(p, result)
    while p.tok.tokType in {tkSymbol, tkAccent}:
      var a = parseIdentColonEquals(p, {})
      addSon(result, a)
      if p.tok.tokType notin {tkComma, tkSemicolon}: break
      getTok(p)
      skipComment(p, a)
    optPar(p)
    eat(p, tkBracketRi)
  elif indentAllowed:
    skipComment(p, result)
    if realInd(p):
      withInd(p):
        skipComment(p, result)
        while true:
          case p.tok.tokType
          of tkSymbol, tkAccent:
            var a = parseIdentColonEquals(p, {})
            skipComment(p, a)
            addSon(result, a)
          of tkEof: break
          else:
            parMessage(p, errIdentifierExpected, p.tok)
            break
          if not sameInd(p): break

proc parseParamList(p: var TParser, retColon = true): PNode =
  #| paramList = '(' declColonEquals ^* (comma/semicolon) ')'
  #| paramListArrow = paramList? ('->' optInd typeDesc)?
  #| paramListColon = paramList? (':' optInd typeDesc)?
  var a: PNode
  result = newNodeP(nkFormalParams, p)
  addSon(result, ast.emptyNode) # return type
  if p.tok.tokType == tkParLe and p.tok.indent < 0:
    getTok(p)
    optInd(p, result)
    while true:
      case p.tok.tokType
      of tkSymbol, tkAccent: 
        a = parseIdentColonEquals(p, {withBothOptional, withPragma})
      of tkParRi: 
        break 
      else: 
        parMessage(p, errTokenExpected, ")")
        break 
      addSon(result, a)
      if p.tok.tokType notin {tkComma, tkSemicolon}: break 
      getTok(p)
      skipComment(p, a)
    optPar(p)
    eat(p, tkParRi)
  let hasRet = if retColon: p.tok.tokType == tkColon
               else: p.tok.tokType == tkOpr and IdentEq(p.tok.ident, "->")
  if hasRet and p.tok.indent < 0:
    getTok(p)
    optInd(p, result)
    result.sons[0] = parseTypeDesc(p)

proc optPragmas(p: var TParser): PNode =
  if p.tok.tokType == tkCurlyDotLe and (p.tok.indent < 0 or realInd(p)):
    result = parsePragma(p)
  else:
    result = ast.emptyNode

proc parseDoBlock(p: var TParser): PNode =
  #| doBlock = 'do' paramListArrow pragmas? colcom stmt
  let info = parLineInfo(p)
  getTok(p)
  let params = parseParamList(p, retColon=false)
  let pragmas = optPragmas(p)
  eat(p, tkColon)
  skipComment(p, result)
  result = newProcNode(nkDo, info, parseStmt(p),
                       params = params,
                       pragmas = pragmas)

proc parseDoBlocks(p: var TParser, call: PNode) =
  #| doBlocks = doBlock ^* IND{=}
  if p.tok.tokType == tkDo:
    addSon(call, parseDoBlock(p))
    while sameInd(p) and p.tok.tokType == tkDo:
      addSon(call, parseDoBlock(p))      

proc parseProcExpr(p: var TParser, isExpr: bool): PNode = 
  #| procExpr = 'proc' paramListColon pragmas? ('=' COMMENT? stmt)?
  # either a proc type or a anonymous proc
  let info = parLineInfo(p)
  getTok(p)
  let hasSignature = p.tok.tokType in {tkParLe, tkColon} and p.tok.indent < 0
  let params = parseParamList(p)
  let pragmas = optPragmas(p)
  if p.tok.tokType == tkEquals and isExpr: 
    getTok(p)
    skipComment(p, result)
    result = newProcNode(nkLambda, info, parseStmt(p),
                         params = params,
                         pragmas = pragmas)
  else:
    result = newNodeI(nkProcTy, info)
    if hasSignature:
      addSon(result, params)
      addSon(result, pragmas)

proc isExprStart(p: TParser): bool = 
  case p.tok.tokType
  of tkSymbol, tkAccent, tkOpr, tkNot, tkNil, tkCast, tkIf, 
     tkProc, tkIterator, tkBind, tkAddr,
     tkParLe, tkBracketLe, tkCurlyLe, tkIntLit..tkCharLit, tkVar, tkRef, tkPtr, 
     tkTuple, tkObject, tkType, tkWhen, tkCase, tkShared:
    result = true
  else: result = false
  
proc parseTypeDescKAux(p: var TParser, kind: TNodeKind, 
                       mode: TPrimaryMode): PNode = 
  result = newNodeP(kind, p)
  getTok(p)
  optInd(p, result)
  if not isOperator(p.tok) and isExprStart(p):
    addSon(result, primary(p, mode))

proc parseExpr(p: var TParser): PNode = 
  #| expr = (ifExpr
  #|       | whenExpr
  #|       | caseExpr
  #|       | tryStmt)
  #|       / simpleExpr
  case p.tok.tokType:
  of tkIf: result = parseIfExpr(p, nkIfExpr)
  of tkWhen: result = parseIfExpr(p, nkWhenExpr)
  of tkCase: result = parseCase(p)
  of tkTry: result = parseTry(p)
  else: result = simpleExpr(p)

proc parseEnum(p: var TParser): PNode
proc parseObject(p: var TParser): PNode
proc parseDistinct(p: var TParser): PNode
proc parseTypeClass(p: var TParser): PNode

proc primary(p: var TParser, mode: TPrimaryMode): PNode = 
  #| typeKeyw = 'var' | 'ref' | 'ptr' | 'shared' | 'type' | 'tuple'
  #|          | 'proc' | 'iterator' | 'distinct' | 'object' | 'enum'
  #| primary = typeKeyw typeDescK
  #|         /  prefixOperator* identOrLiteral primarySuffix*
  #|         / 'addr' primary
  #|         / 'static' primary
  #|         / 'bind' primary
  if isOperator(p.tok):
    let isSigil = IsSigilLike(p.tok)
    result = newNodeP(nkPrefix, p)
    var a = newIdentNodeP(p.tok.ident, p)
    addSon(result, a)
    getTok(p)
    optInd(p, a)
    if isSigil: 
      #XXX prefix operators
      addSon(result, primary(p, pmSkipSuffix))
      result = primarySuffix(p, result)
    else:
      addSon(result, primary(p, pmNormal))
    return
  
  case p.tok.tokType:
  of tkVar: result = parseTypeDescKAux(p, nkVarTy, mode)
  of tkRef: result = parseTypeDescKAux(p, nkRefTy, mode)
  of tkPtr: result = parseTypeDescKAux(p, nkPtrTy, mode)
  of tkShared: result = parseTypeDescKAux(p, nkSharedTy, mode)
  of tkDistinct: result = parseTypeDescKAux(p, nkDistinctTy, mode)
  of tkType: result = parseTypeDescKAux(p, nkTypeOfExpr, mode)
  of tkTuple: result = parseTuple(p, mode == pmTypeDef)
  of tkProc: result = parseProcExpr(p, mode notin {pmTypeDesc, pmTypeDef})
  of tkIterator:
    if mode in {pmTypeDesc, pmTypeDef}:
      result = parseProcExpr(p, false)
      result.kind = nkIteratorTy
    else:
      # no anon iterators for now:
      parMessage(p, errExprExpected, p.tok)
      getTok(p)  # we must consume a token here to prevend endless loops!
      result = ast.emptyNode
  of tkEnum:
    if mode == pmTypeDef:
      result = parseEnum(p)
    else:
      result = newNodeP(nkEnumTy, p)
      getTok(p)
  of tkObject:
    if mode == pmTypeDef:
      result = parseObject(p)
    else:
      result = newNodeP(nkObjectTy, p)
      getTok(p)
  of tkGeneric:
    if mode == pmTypeDef:
      result = parseTypeClass(p)
    else:
      parMessage(p, errInvalidToken, p.tok)
  of tkAddr:
    result = newNodeP(nkAddr, p)
    getTokNoInd(p)
    addSon(result, primary(p, pmNormal))
  of tkStatic:
    result = newNodeP(nkStaticExpr, p)
    getTokNoInd(p)
    addSon(result, primary(p, pmNormal))
  of tkBind:
    result = newNodeP(nkBind, p)
    getTok(p)
    optInd(p, result)
    addSon(result, primary(p, pmNormal))
  else:
    result = identOrLiteral(p, mode)
    if mode != pmSkipSuffix:
      result = primarySuffix(p, result)

proc parseTypeDesc(p: var TParser): PNode =
  #| typeDesc = simpleExpr
  result = simpleExpr(p, pmTypeDesc)

proc parseTypeDefAux(p: var TParser): PNode = 
  #| typeDefAux = simpleExpr
  result = simpleExpr(p, pmTypeDef)

proc makeCall(n: PNode): PNode =
  if n.kind in nkCallKinds:
    result = n
  else:
    result = newNodeI(nkCall, n.info)
    result.add n

proc parseExprStmt(p: var TParser): PNode = 
  #| exprStmt = simpleExpr
  #|          (( '=' optInd expr )
  #|          / ( expr ^+ comma
  #|              doBlocks
  #|               / ':' stmt? ( IND{=} 'of' exprList ':' stmt 
  #|                           | IND{=} 'elif' expr ':' stmt
  #|                           | IND{=} 'except' exprList ':' stmt
  #|                           | IND{=} 'else' ':' stmt )*
  #|            ))?
  var a = simpleExpr(p)
  if p.tok.tokType == tkEquals: 
    getTok(p)
    optInd(p, result)
    var b = parseExpr(p)
    result = newNodeI(nkAsgn, a.info)
    addSon(result, a)
    addSon(result, b)
  else:
    if p.tok.indent < 0 and isExprStart(p):
      result = newNode(nkCommand, a.info, @[a])
      while true:
        var e = parseExpr(p)
        addSon(result, e)
        if p.tok.tokType != tkComma: break 
        getTok(p)
        optInd(p, result)
    else:
      result = a
    if p.tok.tokType == tkDo and p.tok.indent < 0:
      result = makeCall(result)
      parseDoBlocks(p, result)
      return result
    if p.tok.tokType == tkColon and p.tok.indent < 0:
      result = makeCall(result)
      getTok(p)
      skipComment(p, result)
      if p.tok.TokType notin {tkOf, tkElif, tkElse, tkExcept}:
        let body = parseStmt(p)
        addSon(result, newProcNode(nkDo, body.info, body))
      while sameInd(p):
        var b: PNode
        case p.tok.tokType
        of tkOf:
          b = newNodeP(nkOfBranch, p)
          exprList(p, tkColon, b)
        of tkElif: 
          b = newNodeP(nkElifBranch, p)
          getTok(p)
          optInd(p, b)
          addSon(b, parseExpr(p))
          eat(p, tkColon)
        of tkExcept: 
          b = newNodeP(nkExceptBranch, p)
          exprList(p, tkColon, b)
          skipComment(p, b)
        of tkElse: 
          b = newNodeP(nkElse, p)
          getTok(p)
          eat(p, tkColon)
        else: break 
        addSon(b, parseStmt(p))
        addSon(result, b)
        if b.kind == nkElse: break

proc parseImport(p: var TParser, kind: TNodeKind): PNode =
  #| importStmt = 'import' optInd expr
  #|               ((comma expr)*
  #|               / 'except' optInd (expr ^+ comma))
  result = newNodeP(kind, p)
  getTok(p)                   # skip `import` or `export`
  optInd(p, result)
  var a = parseExpr(p)
  addSon(result, a)
  if p.tok.tokType in {tkComma, tkExcept}:
    if p.tok.tokType == tkExcept:
      result.kind = succ(kind)
    getTok(p)
    optInd(p, result)
    while true:
      # was: while p.tok.tokType notin {tkEof, tkSad, tkDed}:
      a = parseExpr(p)
      if a.kind == nkEmpty: break 
      addSon(result, a)
      if p.tok.tokType != tkComma: break 
      getTok(p)
      optInd(p, a)
  #expectNl(p)

proc parseIncludeStmt(p: var TParser): PNode =
  #| includeStmt = 'include' optInd expr ^+ comma
  result = newNodeP(nkIncludeStmt, p)
  getTok(p)                   # skip `import` or `include`
  optInd(p, result)
  while true:
    # was: while p.tok.tokType notin {tkEof, tkSad, tkDed}:
    var a = parseExpr(p)
    if a.kind == nkEmpty: break
    addSon(result, a)
    if p.tok.tokType != tkComma: break 
    getTok(p)
    optInd(p, a)
  #expectNl(p)

proc parseFromStmt(p: var TParser): PNode =
  #| fromStmt = 'from' expr 'import' optInd expr (comma expr)*
  result = newNodeP(nkFromStmt, p)
  getTok(p)                   # skip `from`
  optInd(p, result)
  var a = parseExpr(p)
  addSon(result, a)           #optInd(p, a);
  eat(p, tkImport)
  optInd(p, result)
  while true:
    # p.tok.tokType notin {tkEof, tkSad, tkDed}:
    a = parseExpr(p)
    if a.kind == nkEmpty: break
    addSon(result, a)
    if p.tok.tokType != tkComma: break 
    getTok(p)
    optInd(p, a)
  #expectNl(p)

proc parseReturnOrRaise(p: var TParser, kind: TNodeKind): PNode = 
  #| returnStmt = 'return' optInd expr?
  #| raiseStmt = 'raise' optInd expr?
  #| yieldStmt = 'yield' optInd expr?
  #| discardStmt = 'discard' optInd expr?
  #| breakStmt = 'break' optInd expr?
  #| continueStmt = 'break' optInd expr?
  result = newNodeP(kind, p)
  getTok(p)
  if p.tok.tokType == tkComment:
    skipComment(p, result)
    addSon(result, ast.emptyNode)
  elif p.tok.indent >= 0 and p.tok.indent <= p.currInd or
      p.tok.tokType == tkEof:
    # NL terminates:
    addSon(result, ast.emptyNode)
  else:
    addSon(result, parseExpr(p))

proc parseIfOrWhen(p: var TParser, kind: TNodeKind): PNode =
  #| condStmt = expr colcom stmt COMMENT?
  #|            (IND{=} 'elif' expr colcom stmt)*
  #|            (IND{=} 'else' colcom stmt)?
  #| ifStmt = 'if' condStmt
  #| whenStmt = 'when' condStmt
  result = newNodeP(kind, p)
  while true:
    getTok(p)                 # skip `if`, `when`, `elif`
    var branch = newNodeP(nkElifBranch, p)
    optInd(p, branch)
    addSon(branch, parseExpr(p))
    eat(p, tkColon)
    skipComment(p, branch)
    addSon(branch, parseStmt(p))
    skipComment(p, branch)
    addSon(result, branch)
    if p.tok.tokType != tkElif or not sameOrNoInd(p): break
  if p.tok.tokType == tkElse and sameOrNoInd(p):
    var branch = newNodeP(nkElse, p)
    eat(p, tkElse)
    eat(p, tkColon)
    skipComment(p, branch)
    addSon(branch, parseStmt(p))
    addSon(result, branch)

proc parseWhile(p: var TParser): PNode =
  #| whileStmt = 'while' expr colcom stmt
  result = newNodeP(nkWhileStmt, p)
  getTok(p)
  optInd(p, result)
  addSon(result, parseExpr(p))
  colcom(p, result)
  addSon(result, parseStmt(p))

proc parseCase(p: var TParser): PNode =
  #| ofBranch = 'of' exprList colcom stmt
  #| ofBranches = ofBranch (IND{=} ofBranch)*
  #|                       (IND{=} 'elif' expr colcom stmt)*
  #|                       (IND{=} 'else' colcom stmt)?
  #| caseStmt = 'case' expr ':'? COMMENT?
  #|             (IND{>} ofBranches DED
  #|             | IND{=} ofBranches)
  var
    b: PNode
    inElif= false
    wasIndented = false
  result = newNodeP(nkCaseStmt, p)
  getTok(p)
  addSon(result, parseExpr(p))
  if p.tok.tokType == tkColon: getTok(p)
  skipComment(p, result)
  
  let oldInd = p.currInd
  if realInd(p):
    p.currInd = p.tok.indent
    wasIndented = true
  
  while sameInd(p):
    case p.tok.tokType
    of tkOf:
      if inElif: break
      b = newNodeP(nkOfBranch, p)
      exprList(p, tkColon, b)
    of tkElif:
      inElif = true
      b = newNodeP(nkElifBranch, p)
      getTok(p)
      optInd(p, b)
      addSon(b, parseExpr(p))
      eat(p, tkColon)
    of tkElse:
      b = newNodeP(nkElse, p)
      getTok(p)
      eat(p, tkColon)
    else: break
    skipComment(p, b)
    addSon(b, parseStmt(p))
    addSon(result, b)
    if b.kind == nkElse: break
  
  if wasIndented:
    p.currInd = oldInd
    
proc parseTry(p: var TParser): PNode =
  #| tryStmt = 'try' colcom stmt &(IND{=}? 'except'|'finally')
  #|            (IND{=}? 'except' exprList colcom stmt)*
  #|            (IND{=}? 'finally' colcom stmt)?
  result = newNodeP(nkTryStmt, p)
  getTok(p)
  eat(p, tkColon)
  skipComment(p, result)
  addSon(result, parseStmt(p))
  var b: PNode = nil
  while sameOrNoInd(p):
    case p.tok.tokType
    of tkExcept: 
      b = newNodeP(nkExceptBranch, p)
      exprList(p, tkColon, b)
    of tkFinally: 
      b = newNodeP(nkFinally, p)
      getTokNoInd(p)
      eat(p, tkColon)
    else: break
    skipComment(p, b)
    addSon(b, parseStmt(p))
    addSon(result, b)
    if b.kind == nkFinally: break 
  if b == nil: parMessage(p, errTokenExpected, "except")

proc parseExceptBlock(p: var TParser, kind: TNodeKind): PNode =
  #| exceptBlock = 'except' colcom stmt
  result = newNodeP(kind, p)
  getTokNoInd(p)
  colcom(p, result)
  addSon(result, parseStmt(p))

proc parseFor(p: var TParser): PNode =
  #| forStmt = 'for' (identWithPragma ^+ comma) 'in' expr colcom stmt
  result = newNodeP(nkForStmt, p)
  getTokNoInd(p)
  var a = identWithPragma(p)
  addSon(result, a)
  while p.tok.tokType == tkComma:
    getTok(p)
    optInd(p, a)
    a = identWithPragma(p)
    addSon(result, a)
  eat(p, tkIn)
  addSon(result, parseExpr(p))
  colcom(p, result)
  addSon(result, parseStmt(p))

proc parseBlock(p: var TParser): PNode = 
  #| blockStmt = 'block' symbol? colcom stmt
  result = newNodeP(nkBlockStmt, p)
  getTokNoInd(p)
  if p.tok.tokType == tkColon: addSon(result, ast.emptyNode)
  else: addSon(result, parseSymbol(p))
  colcom(p, result)
  addSon(result, parseStmt(p))

proc parseStatic(p: var TParser): PNode =
  #| staticStmt = 'static' colcom stmt
  result = newNodeP(nkStaticStmt, p)
  getTokNoInd(p)
  colcom(p, result)
  addSon(result, parseStmt(p))
  
proc parseAsm(p: var TParser): PNode =
  #| asmStmt = 'asm' pragma? (STR_LIT | RSTR_LIT | TRIPLE_STR_LIT)
  result = newNodeP(nkAsmStmt, p)
  getTokNoInd(p)
  if p.tok.tokType == tkCurlyDotLe: addSon(result, parsePragma(p))
  else: addSon(result, ast.emptyNode)
  case p.tok.tokType
  of tkStrLit: addSon(result, newStrNodeP(nkStrLit, p.tok.literal, p))
  of tkRStrLit: addSon(result, newStrNodeP(nkRStrLit, p.tok.literal, p))
  of tkTripleStrLit: addSon(result, 
                            newStrNodeP(nkTripleStrLit, p.tok.literal, p))
  else: 
    parMessage(p, errStringLiteralExpected)
    addSon(result, ast.emptyNode)
    return 
  getTok(p)

proc parseGenericParam(p: var TParser): PNode =
  #| genericParam = symbol (comma symbol)* (colon expr)? ('=' optInd expr)?
  var a: PNode
  result = newNodeP(nkIdentDefs, p)
  while true: 
    case p.tok.tokType
    of tkSymbol, tkAccent: 
      a = parseSymbol(p)
      if a.kind == nkEmpty: return 
    else: break 
    addSon(result, a)
    if p.tok.tokType != tkComma: break 
    getTok(p)
    optInd(p, a)
  if p.tok.tokType == tkColon: 
    getTok(p)
    optInd(p, result)
    addSon(result, parseExpr(p))
  else: 
    addSon(result, ast.emptyNode)
  if p.tok.tokType == tkEquals: 
    getTok(p)
    optInd(p, result)
    addSon(result, parseExpr(p))
  else: 
    addSon(result, ast.emptyNode)

proc parseGenericParamList(p: var TParser): PNode = 
  #| genericParamList = '[' optInd
  #|   genericParam ^* (comma/semicolon) optPar ']'
  result = newNodeP(nkGenericParams, p)
  getTok(p)
  optInd(p, result)
  while p.tok.tokType in {tkSymbol, tkAccent}: 
    var a = parseGenericParam(p)
    addSon(result, a)
    if p.tok.tokType notin {tkComma, tkSemicolon}: break 
    getTok(p)
    skipComment(p, a)
  optPar(p)
  eat(p, tkBracketRi)

proc parsePattern(p: var TParser): PNode =
  #| pattern = '{' stmt '}'
  eat(p, tkCurlyLe)
  result = parseStmt(p)
  eat(p, tkCurlyRi)

proc validInd(p: var TParser): bool =
  result = p.tok.indent < 0 or p.tok.indent > p.currInd

proc parseRoutine(p: var TParser, kind: TNodeKind): PNode = 
  #| indAndComment = (IND{>} COMMENT)? | COMMENT?
  #| routine = optInd identVis pattern? genericParamList?
  #|   paramListColon pragma? ('=' COMMENT? stmt)? indAndComment
  result = newNodeP(kind, p)
  getTok(p)
  optInd(p, result)
  addSon(result, identVis(p))
  if p.tok.tokType == tkCurlyLe and p.validInd: addSon(result, p.parsePattern)
  else: addSon(result, ast.emptyNode)
  if p.tok.tokType == tkBracketLe and p.validInd:
    result.add(p.parseGenericParamList)
  else:
    addSon(result, ast.emptyNode)
  addSon(result, p.parseParamList)
  if p.tok.tokType == tkCurlyDotLe and p.validInd: addSon(result, p.parsePragma)
  else: addSon(result, ast.emptyNode)
  # empty exception tracking:
  addSon(result, ast.emptyNode)
  if p.tok.tokType == tkEquals and p.validInd: 
    getTok(p)
    skipComment(p, result)
    addSon(result, parseStmt(p))
  else:
    addSon(result, ast.emptyNode)
  indAndComment(p, result)
  
proc newCommentStmt(p: var TParser): PNode =
  #| commentStmt = COMMENT
  result = newNodeP(nkCommentStmt, p)
  result.comment = p.tok.literal
  getTok(p)

type
  TDefParser = proc (p: var TParser): PNode {.nimcall.}

proc parseSection(p: var TParser, kind: TNodeKind,
                  defparser: TDefParser): PNode =
  #| section(p) = COMMENT? p / (IND{>} (p / COMMENT)^+IND{=} DED)
  result = newNodeP(kind, p)
  getTok(p)
  skipComment(p, result)
  if realInd(p):
    withInd(p):
      skipComment(p, result)
      while sameInd(p):
        case p.tok.tokType
        of tkSymbol, tkAccent: 
          var a = defparser(p)
          skipComment(p, a)
          addSon(result, a)
        of tkComment: 
          var a = newCommentStmt(p)
          addSon(result, a)
        else: 
          parMessage(p, errIdentifierExpected, p.tok)
          break
    if result.len == 0: parMessage(p, errIdentifierExpected, p.tok)
  elif p.tok.tokType in {tkSymbol, tkAccent, tkParLe} and p.tok.indent < 0:
    # tkParLe is allowed for ``var (x, y) = ...`` tuple parsing
    addSon(result, defparser(p))
  else: 
    parMessage(p, errIdentifierExpected, p.tok)
  
proc parseConstant(p: var TParser): PNode =
  #| constant = identWithPragma (colon typedesc)? '=' optInd expr indAndComment
  result = newNodeP(nkConstDef, p)
  addSon(result, identWithPragma(p))
  if p.tok.tokType == tkColon: 
    getTok(p)
    optInd(p, result)
    addSon(result, parseTypeDesc(p))
  else: 
    addSon(result, ast.emptyNode)
  eat(p, tkEquals)
  optInd(p, result)
  addSon(result, parseExpr(p))
  indAndComment(p, result)
  
proc parseEnum(p: var TParser): PNode = 
  #| enum = 'enum' optInd (symbol optInd ('=' optInd expr COMMENT?)? comma?)+
  result = newNodeP(nkEnumTy, p)
  getTok(p)
  addSon(result, ast.emptyNode)
  optInd(p, result)
  while true:
    var a = parseSymbol(p)
    if p.tok.indent >= 0 and p.tok.indent <= p.currInd:
      add(result, a)
      break
    if p.tok.tokType == tkEquals and p.tok.indent < 0: 
      getTok(p)
      optInd(p, a)
      var b = a
      a = newNodeP(nkEnumFieldDef, p)
      addSon(a, b)
      addSon(a, parseExpr(p))
      skipComment(p, a)
    if p.tok.tokType == tkComma and p.tok.indent < 0:
      getTok(p)
      rawSkipComment(p, a)
    else:
      skipComment(p, a)
    addSon(result, a)
    if p.tok.indent >= 0 and p.tok.indent <= p.currInd or
        p.tok.tokType == tkEof:
      break
  if result.len <= 1:
    lexMessage(p.lex, errIdentifierExpected, prettyTok(p.tok))

proc parseObjectPart(p: var TParser): PNode
proc parseObjectWhen(p: var TParser): PNode = 
  #| objectWhen = 'when' expr colcom objectPart COMMENT?
  #|             ('elif' expr colcom objectPart COMMENT?)*
  #|             ('else' colcom objectPart COMMENT?)?
  result = newNodeP(nkRecWhen, p)
  while sameInd(p): 
    getTok(p)                 # skip `when`, `elif`
    var branch = newNodeP(nkElifBranch, p)
    optInd(p, branch)
    addSon(branch, parseExpr(p))
    colcom(p, branch)
    addSon(branch, parseObjectPart(p))
    skipComment(p, branch)
    addSon(result, branch)
    if p.tok.tokType != tkElif: break
  if p.tok.tokType == tkElse and sameInd(p):
    var branch = newNodeP(nkElse, p)
    eat(p, tkElse)
    colcom(p, branch)
    addSon(branch, parseObjectPart(p))
    skipComment(p, branch)
    addSon(result, branch)

proc parseObjectCase(p: var TParser): PNode = 
  #| objectBranch = 'of' exprList colcom objectPart
  #| objectBranches = objectBranch (IND{=} objectBranch)*
  #|                       (IND{=} 'elif' expr colcom objectPart)*
  #|                       (IND{=} 'else' colcom objectPart)?
  #| objectCase = 'case' identWithPragma ':' typeDesc ':'? COMMENT?
  #|             (IND{>} objectBranches DED
  #|             | IND{=} objectBranches)
  result = newNodeP(nkRecCase, p)
  getTokNoInd(p)
  var a = newNodeP(nkIdentDefs, p)
  addSon(a, identWithPragma(p))
  eat(p, tkColon)
  addSon(a, parseTypeDesc(p))
  addSon(a, ast.emptyNode)
  addSon(result, a)
  if p.tok.tokType == tkColon: getTok(p)
  skipComment(p, result)
  var wasIndented = false
  let oldInd = p.currInd
  if realInd(p):
    p.currInd = p.tok.indent
    wasIndented = true
  while sameInd(p):
    var b: PNode
    case p.tok.tokType
    of tkOf: 
      b = newNodeP(nkOfBranch, p)
      exprList(p, tkColon, b)
    of tkElse: 
      b = newNodeP(nkElse, p)
      getTok(p)
      eat(p, tkColon)
    else: break 
    skipComment(p, b)
    var fields = parseObjectPart(p)
    if fields.kind == nkEmpty:
      parMessage(p, errIdentifierExpected, p.tok)
      fields = newNodeP(nkNilLit, p) # don't break further semantic checking
    addSon(b, fields)
    addSon(result, b)
    if b.kind == nkElse: break
  if wasIndented:
    p.currInd = oldInd
  
proc parseObjectPart(p: var TParser): PNode = 
  #| objectPart = IND{>} objectPart^+IND{=} DED
  #|            / objectWhen / objectCase / 'nil' / declColonEquals
  if realInd(p):
    result = newNodeP(nkRecList, p)
    withInd(p):
      rawSkipComment(p, result)
      while sameInd(p):
        case p.tok.tokType
        of tkCase, tkWhen, tkSymbol, tkAccent, tkNil: 
          addSon(result, parseObjectPart(p))
        else:
          parMessage(p, errIdentifierExpected, p.tok)
          break
  else:
    case p.tok.tokType
    of tkWhen:
      result = parseObjectWhen(p)
    of tkCase:
      result = parseObjectCase(p)
    of tkSymbol, tkAccent:
      result = parseIdentColonEquals(p, {withPragma})
      skipComment(p, result)
    of tkNil:
      result = newNodeP(nkNilLit, p)
      getTok(p)
    else:
      result = ast.emptyNode
  
proc parseObject(p: var TParser): PNode = 
  #| object = 'object' pragma? ('of' typeDesc)? COMMENT? objectPart
  result = newNodeP(nkObjectTy, p)
  getTok(p)
  if p.tok.tokType == tkCurlyDotLe and p.validInd:
    addSon(result, parsePragma(p))
  else:
    addSon(result, ast.emptyNode)
  if p.tok.tokType == tkOf and p.tok.indent < 0:
    var a = newNodeP(nkOfInherit, p)
    getTok(p)
    addSon(a, parseTypeDesc(p))
    addSon(result, a)
  else: 
    addSon(result, ast.emptyNode)
  if p.tok.tokType == tkComment:
    skipComment(p, result)
  # an initial IND{>} HAS to follow:
  if not realInd(p):
    addSon(result, emptyNode)
    return
  addSon(result, parseObjectPart(p))

proc parseTypeClass(p: var TParser): PNode =
  result = newNodeP(nkTypeClassTy, p)
  getTok(p)
  addSon(result, p.parseSymbol)
  if p.tok.tokType == tkCurlyDotLe and p.validInd:
    addSon(result, parsePragma(p))
  else:
    addSon(result, ast.emptyNode)
  if p.tok.tokType == tkOf and p.tok.indent < 0:
    var a = newNodeP(nkOfInherit, p)
    getTok(p)
    while true:
      addSon(a, parseTypeDesc(p))
      if p.tok.tokType != tkComma: break
      getTok(p)
    addSon(result, a)
  else:
    addSon(result, ast.emptyNode)
  if p.tok.tokType == tkComment:
    skipComment(p, result)
  # an initial IND{>} HAS to follow:
  if not realInd(p):
    addSon(result, emptyNode)
  else:
    addSon(result, parseStmt(p))

proc parseDistinct(p: var TParser): PNode = 
  #| distinct = 'distinct' optInd typeDesc
  result = newNodeP(nkDistinctTy, p)
  getTok(p)
  optInd(p, result)
  addSon(result, parseTypeDesc(p))

proc parseTypeDef(p: var TParser): PNode = 
  #| typeDef = identWithPragma genericParamList? '=' optInd typeDefAux
  #|             indAndComment?
  result = newNodeP(nkTypeDef, p)
  addSon(result, identWithPragma(p))
  if p.tok.tokType == tkBracketLe and p.validInd:
    addSon(result, parseGenericParamList(p))
  else:
    addSon(result, ast.emptyNode)
  if p.tok.tokType == tkEquals:
    getTok(p)
    optInd(p, result)
    addSon(result, parseTypeDefAux(p))
  else:
    addSon(result, ast.emptyNode)
  indAndComment(p, result)    # special extension!
  
proc parseVarTuple(p: var TParser): PNode =
  #| varTuple = '(' optInd identWithPragma ^+ comma optPar ')' '=' optInd expr
  result = newNodeP(nkVarTuple, p)
  getTok(p)                   # skip '('
  optInd(p, result)
  while p.tok.tokType in {tkSymbol, tkAccent}: 
    var a = identWithPragma(p)
    addSon(result, a)
    if p.tok.tokType != tkComma: break 
    getTok(p)
    skipComment(p, a)
  addSon(result, ast.emptyNode)         # no type desc
  optPar(p)
  eat(p, tkParRi)
  eat(p, tkEquals)
  optInd(p, result)
  addSon(result, parseExpr(p))

proc parseVariable(p: var TParser): PNode =
  #| variable = (varTuple / identColonEquals) indAndComment
  if p.tok.tokType == tkParLe: result = parseVarTuple(p)
  else: result = parseIdentColonEquals(p, {withPragma})
  indAndComment(p, result)
  
proc parseBind(p: var TParser, k: TNodeKind): PNode =
  #| bindStmt = 'bind' optInd qualifiedIdent ^+ comma
  #| mixinStmt = 'mixin' optInd qualifiedIdent ^+ comma
  result = newNodeP(k, p)
  getTok(p)
  optInd(p, result)
  while true:
    var a = qualifiedIdent(p)
    addSon(result, a)
    if p.tok.tokType != tkComma: break
    getTok(p)
    optInd(p, a)
  #expectNl(p)
  
proc parseStmtPragma(p: var TParser): PNode =
  #| pragmaStmt = pragma (':' COMMENT? stmt)?
  result = parsePragma(p)
  if p.tok.tokType == tkColon and p.tok.indent < 0:
    let a = result
    result = newNodeI(nkPragmaBlock, a.info)
    getTok(p)
    skipComment(p, result)
    result.add a
    result.add parseStmt(p)

proc simpleStmt(p: var TParser): PNode = 
  #| simpleStmt = ((returnStmt | raiseStmt | yieldStmt | discardStmt | breakStmt
  #|            | continueStmt | pragmaStmt | importStmt | exportStmt | fromStmt
  #|            | includeStmt | commentStmt) / exprStmt) COMMENT?
  #|
  case p.tok.tokType
  of tkReturn: result = parseReturnOrRaise(p, nkReturnStmt)
  of tkRaise: result = parseReturnOrRaise(p, nkRaiseStmt)
  of tkYield: result = parseReturnOrRaise(p, nkYieldStmt)
  of tkDiscard: result = parseReturnOrRaise(p, nkDiscardStmt)
  of tkBreak: result = parseReturnOrRaise(p, nkBreakStmt)
  of tkContinue: result = parseReturnOrRaise(p, nkContinueStmt)
  of tkCurlyDotLe: result = parseStmtPragma(p)
  of tkImport: result = parseImport(p, nkImportStmt)
  of tkExport: result = parseImport(p, nkExportStmt)
  of tkFrom: result = parseFromStmt(p)
  of tkInclude: result = parseIncludeStmt(p)
  of tkComment: result = newCommentStmt(p)
  else:
    if isExprStart(p): result = parseExprStmt(p)
    else: result = ast.emptyNode
  if result.kind notin {nkEmpty, nkCommentStmt}: skipComment(p, result)
  
proc complexOrSimpleStmt(p: var TParser): PNode =
  #| complexOrSimpleStmt = (ifStmt | whenStmt | whileStmt
  #|                     | tryStmt | finallyStmt | exceptStmt | forStmt
  #|                     | blockStmt | staticStmt | asmStmt
  #|                     | 'proc' routine
  #|                     | 'method' routine
  #|                     | 'iterator' routine
  #|                     | 'macro' routine
  #|                     | 'template' routine
  #|                     | 'converter' routine
  #|                     | 'type' section(typeDef)
  #|                     | 'const' section(constant)
  #|                     | ('let' | 'var') section(variable)
  #|                     | bindStmt | mixinStmt)
  #|                     / simpleStmt
  case p.tok.tokType
  of tkIf: result = parseIfOrWhen(p, nkIfStmt)
  of tkWhile: result = parseWhile(p)
  of tkCase: result = parseCase(p)
  of tkTry: result = parseTry(p)
  of tkFinally: result = parseExceptBlock(p, nkFinally)
  of tkExcept: result = parseExceptBlock(p, nkExceptBranch)
  of tkFor: result = parseFor(p)
  of tkBlock: result = parseBlock(p)
  of tkStatic: result = parseStatic(p)
  of tkAsm: result = parseAsm(p)
  of tkProc: result = parseRoutine(p, nkProcDef)
  of tkMethod: result = parseRoutine(p, nkMethodDef)
  of tkIterator: result = parseRoutine(p, nkIteratorDef)
  of tkMacro: result = parseRoutine(p, nkMacroDef)
  of tkTemplate: result = parseRoutine(p, nkTemplateDef)
  of tkConverter: result = parseRoutine(p, nkConverterDef)
  of tkType: result = parseSection(p, nkTypeSection, parseTypeDef)
  of tkConst: result = parseSection(p, nkConstSection, parseConstant)
  of tkLet: result = parseSection(p, nkLetSection, parseVariable)
  of tkWhen: result = parseIfOrWhen(p, nkWhenStmt)
  of tkVar: result = parseSection(p, nkVarSection, parseVariable)
  of tkBind: result = parseBind(p, nkBindStmt)
  of tkMixin: result = parseBind(p, nkMixinStmt)
  of tkUsing: result = parseBind(p, nkUsingStmt)
  else: result = simpleStmt(p)
  
proc parseStmt(p: var TParser): PNode =
  #| stmt = (IND{>} complexOrSimpleStmt^+(IND{=} / ';') DED)
  #|      / simpleStmt ^+ ';'
  if p.tok.indent > p.currInd:
    result = newNodeP(nkStmtList, p)
    withInd(p):
      while true:
        if p.tok.indent == p.currInd:
          nil
        elif p.tok.tokType == tkSemicolon:
          while p.tok.tokType == tkSemicolon: getTok(p)
        else:
          if p.tok.indent > p.currInd:
            parMessage(p, errInvalidIndentation)
          break
        if p.tok.toktype in {tkCurlyRi, tkParRi, tkCurlyDotRi, tkBracketRi}:
          # XXX this ensures tnamedparamanonproc still compiles;
          # deprecate this syntax later
          break
        var a = complexOrSimpleStmt(p)
        if a.kind != nkEmpty:
          addSon(result, a)
        else:
          parMessage(p, errExprExpected, p.tok)
          getTok(p)
  else:
    # the case statement is only needed for better error messages:
    case p.tok.tokType
    of tkIf, tkWhile, tkCase, tkTry, tkFor, tkBlock, tkAsm, tkProc, tkIterator,
       tkMacro, tkType, tkConst, tkWhen, tkVar:
      parMessage(p, errComplexStmtRequiresInd)
      result = ast.emptyNode
    else:
      result = newNodeP(nkStmtList, p)
      while true:
        if p.tok.indent >= 0: parMessage(p, errInvalidIndentation)     
        let a = simpleStmt(p)
        if a.kind == nkEmpty: parMessage(p, errExprExpected, p.tok)
        result.add(a)
        if p.tok.tokType != tkSemicolon: break
        getTok(p)
  
proc parseAll(p: var TParser): PNode = 
  result = newNodeP(nkStmtList, p)
  while p.tok.tokType != tkEof: 
    var a = complexOrSimpleStmt(p)
    if a.kind != nkEmpty: 
      addSon(result, a)    
    else:
      parMessage(p, errExprExpected, p.tok)
      # bugfix: consume a token here to prevent an endless loop:
      getTok(p)
    if p.tok.indent != 0:
      parMessage(p, errInvalidIndentation)

proc parseTopLevelStmt(p: var TParser): PNode =
  result = ast.emptyNode
  while true:
    if p.tok.indent != 0: 
      if p.firstTok and p.tok.indent < 0: nil
      else: parMessage(p, errInvalidIndentation)
    p.firstTok = false
    case p.tok.tokType
    of tkSemicolon: getTok(p)
    of tkEof: break
    else:
      result = complexOrSimpleStmt(p)
      if result.kind == nkEmpty: parMessage(p, errExprExpected, p.tok)
      break

proc parseString(s: string, filename: string = "", line: int = 0): PNode =
  var stream = LLStreamOpen(s)
  stream.lineOffset = line

  var parser: TParser
  OpenParser(parser, filename, stream)

  result = parser.parseAll
  CloseParser(parser)
