import macros
export macros
import sets
export sets
import tables
export tables
import strutils
import hashes
import os
export os

type
  MessageStatus = enum
    Todo,
    Done,
    Redo,
    Gone,
  
  LocaleMessage = tuple
    status: MessageStatus
    hashval: int
    key: string
    value: NimNode


proc makeIntoClosure*(x:NimNode):NimNode {.compileTime.} =
  ## Given a lambda node, set the pragma so that it's a closure proc
  if x.kind == nnkLambda:
    result = x.copyNimTree()
    result[4] = nnkPragma.newTree(
      newIdentNode("closure")
    )
  else:
    result = x

proc computeHash(s:string):int =
  result = (($hash(s)).substr(0,4).alignLeft(5, '0')).parseInt()

proc computeHash(node:NimNode):int {.compileTime.} =
  computeHash($node.toStrLit())

proc generateKey*(x:string):string {.compileTime.} =
  ## Given a translation string, generate a unique, but
  result = "s_"
  for c in x.toLower():
    if c in 'a'..'z' or c in '0'..'9':
      result.add(c)
      if result.len > 10:
        break
  result.add($computeHash(x))

proc dedent*(x:string):string =
  var chars = 0
  for line in x.split('\l'):
    if line.strip() != "":
      chars = line.len - line.strip(leading = true, trailing = false).len
      break
  
  result = unindent(x, chars)



template intlCatalog*(name:string) =
  ## Create a new message catalog.  You typically only need one per program.
  ##
  ## This makes a new set of `tr` procs for marking messages.
  import tables
  export tables
  
  var extracted_messages {.compileTime, genSym.} = newOrderedTable[string,NimNode]()
  var base_message_tab {.compileTime, genSym.} = newOrderedTable[string,NimNode]()
  var locale_messages {.compileTime, genSym.} = newOrderedTable[string,seq[LocaleMessage]]()
  let message_type_name {.compileTime, genSym.} = "Messages_" & name
  let selectedMessages_varname {.compileTime, genSym.} = "selectedMessages_" & name
  let chooser_table_varname {.compileTime, genSym.} = "localeChoosers_" & name

  proc handleTr(key:string, message:NimNode):NimNode {.compileTime.} =
    ## Generate the NimNode that will become the localised value
    # Extract message for later inclusion in the catalog
    extracted_messages[key] = message.copyNimTree()

    # Produce the code to get the right value at runtime/compile time
    if base_message_tab.hasKey(key):
      # This message is in the catalog.
      nnkDotExpr.newTree(
        newIdentNode(selectedMessages_varname),
        newIdentNode(key)
      )
    else:
      # This message is not known to the catalog.
      # Use the source-provided value.
      message

  macro tr*(key:string, message:untyped):untyped =
    ## TODO
    handleTr($key, message.copyNimTree())

  macro tr*(message:untyped):untyped =
    ## TODO
    let sanikey = generateKey($(message.copyNimTree().toStrLit()))
    handleTr(sanikey, message.copyNimTree())

  proc setLocaleMacro(locale:NimNode):NimNode =
    result = nnkStmtList.newTree(
      nnkAsgn.newTree(
        newIdentNode(selectedMessages_varname),
        nnkCall.newTree(
          nnkBracketExpr.newTree(
            newIdentNode(chooser_table_varname),
            locale,
          )
        )
      )
    )

  macro setLocale*(locale:string):untyped =
    setLocaleMacro(locale)
  
  proc staticListDir(dirname:string):string {.compileTime.} =
    gorge("ls " & dirname)
  
  proc staticCreateDir(dirname:string):bool {.compileTime.} =
    return gorgeEx("mkdir " & dirname).exitCode == 0

  proc staticIntlPostlude*(baseDir:string, autoSubDir:string) {.compileTime.} =
    ## Save extracted strings to files
    let autoDir = if baseDir != "" and autoSubDir != "": baseDir/autoSubDir else: ""
    if autoDir != "":
      echo "intl: autoDir=", autoDir
      if not staticCreateDir(autoDir):
        echo "intl: Failed to make autoDir: " & autoDir
    
    var postludeParts:seq[string]
    postludeParts.add "## ==== intl postlude ===="

    # Generate an updated baseMessages block
    var baseMessages = nnkStmtList.newTree()
    for k,v in extracted_messages.pairs:
      baseMessages.add(nnkCommand.newTree(
        newIdentNode("msg"),
        newLit($k),
        v,
      ))
    let baseMessages_string = $nnkCall.newTree(
      newIdentNode("baseMessages"),
      nnkStmtList.newTree(baseMessages),
    ).toStrLit()
    postludeParts.add(baseMessages_string)
    
    if autoDir != "":
      writeFile(autoDir/"base.nim", dedent("""
      import intl
      export intl
      intlCatalog """ & "\"" & name & "\"\L" & """
      """) & baseMessages_string)
      echo "intl: wrote " & autoSubDir/"base.nim"
      let nimfiles = staticListDir(autoDir).splitLines()
      for filename in nimfiles:
        let locale_name = filename.changeFileExt("")
        if locale_name != "base" and locale_name != "all":
          if not locale_messages.hasKey(locale_name):
            locale_messages[locale_name] = newSeq[LocaleMessage]()

    # Generate an updated locale messages block
    for locale,messages in locale_messages.pairs:
      var words:seq[NimNode]
      var encountered = initHashSet[string]()
      # Existing translations
      for message in messages:
        var status = "todo"
        case message.status
        of Gone: status = "gone"
        of Done: status = "done"
        of Todo: status = "todo"
        of Redo: status = "redo"

        var hashval:int = message.hashval
        var comment:string
        if extracted_messages.hasKey(message.key):
          encountered.incl(message.key)
          hashval = computeHash(extracted_messages[message.key])
          if hashval != message.hashval and (message.status != Todo):
            # The key is the same, but the string has changed.
            # Mark this as needing to be rechecked
            status = "redo"
            comment = "New value: " & $extracted_messages[message.key].toStrLit()
        else:
          status = "gone"

        words.add(nnkCommand.newTree(
          newIdentNode(status),
          newLit(hashval),
          newLit(message.key),
          message.value,
        ))
        if comment != "":
          words.add(newCommentStmtNode(comment))
      
      # Newly extracted messages 
      for k,v in extracted_messages.pairs:
        if k in encountered:
          continue
        words.add(nnkCommand.newTree(
          newIdentNode("todo"),
          newLit(computeHash(v)),
          newLit(k),
          v,
        ))
      
      let localeMessages_string = $nnkCommand.newTree(
        newIdentNode("messages"),
        newLit(locale),
        nnkStmtList.newTree(words),
      ).toStrLit()
      postludeParts.add ""
      postludeParts.add localeMessages_string
      if autoDir != "":
        let filename = autoDir/locale & ".nim"
        writeFile(filename, dedent"""
        import ./base
        """ & localeMessages_string)
        echo "intl: wrote " & autoSubDir/filename.extractFilename()
    
    if autoDir != "":
      var guts = dedent"""
      import intl
      export intl
      import ./base
      export base
      """
      for locale in locale_messages.keys:
        guts.add("import ./" & locale & "\l")

      writeFile(autoDir/"all.nim", guts)
      echo "intl: wrote " & autoSubDir/"all.nim"
    postludeParts.add "## ==== end intl postlude ===="
    echo postludeParts.join("\l")

  template intlPostlude*(callingSrcPath = "", autoDir = "") =
    ## Execute the intl postlude.  Call this at the very end
    ## of your main Nim file.
    ## 
    ## To manage messages yourself, call without arguments:
    ##    intlPostlude()
    ## 
    ## To have intl manage messages for you, call like this:
    ##    intlPostlude(currentSourcePath(), "trans")
    static:
      staticIntlPostlude(callingSrcPath.parentDir(), autoDir)
  
  template baseMessages*(body:untyped):untyped =
    ## Define the set of messages within this catalog
    
    block:
      static:
        macro msg(key:string, otherthing:untyped) =
          base_message_tab[$key] = otherthing.copyNimTree()
        body
    
    macro mkMessageType():untyped =
      ## Make
      ##   type Messages_X: tuple
      ##      ...attrs
      var tuple_attrs = nnkTupleTy.newTree()
      for k,v in base_message_tab.pairs:
        case v.kind
        of nnkStrLit, nnkRStrLit:
          tuple_attrs.add(nnkIdentDefs.newTree(
            newIdentNode(k),
            newIdentNode("string"),
            newEmptyNode(),
          ))
        of nnkLambda:
          let paramsNode = v[3]
          tuple_attrs.add(nnkIdentDefs.newTree(
            newIdentNode(k),
            nnkProcTy.newTree(
              paramsNode.copyNimTree(),
              newEmptyNode()
            ),
            newEmptyNode()
          ))
        else:
          # TODO how do I use {.warning.} for this?
          echo "WARNING: Unexpected base message type in " & k & ": " & $v.kind
      nnkStmtList.newTree(
        nnkTypeSection.newTree(
          nnkTypeDef.newTree(
            nnkPostfix.newTree(
              newIdentNode("*"),
              newIdentNode(message_type_name),
            ),
            newEmptyNode(),
            tuple_attrs,
          )
        )
      )
    
    mkMessageType()

    macro mkSelectedMessagesVar():untyped =
      ## Make
      ##   var selectedMessages_X*:Messages_X = (...defaults...)
      var values = nnkTupleConstr.newTree()
      for k,v in base_message_tab.pairs:
        values.add(v.makeIntoClosure())
      nnkStmtList.newTree(
        nnkVarSection.newTree(
          nnkIdentDefs.newTree(
            nnkPostfix.newTree(
              newIdentNode("*"),
              newIdentNode(selectedMessages_varname)
            ),
            newIdentNode(message_type_name),
            values,
          )
        )
      )
    mkSelectedMessagesVar()

    macro mkChooserTable():untyped =
      ## Makes
      ##   var localeSelectors_X* = newTable[string, proc():Messages_X]()
      nnkStmtList.newTree(
        nnkVarSection.newTree(
          nnkIdentDefs.newTree(
            nnkPostfix.newTree(
              newIdentNode("*"),
              newIdentNode(chooser_table_varname)
            ),
            newEmptyNode(),
            nnkCall.newTree(
              nnkBracketExpr.newTree(
                newIdentNode("newTable"),
                newIdentNode("string"),
                nnkProcTy.newTree(
                  nnkFormalParams.newTree(
                    newIdentNode(message_type_name)
                  ),
                  newEmptyNode()
                )
              )
            )
          )
        )
      )
    mkChooserTable()

  
  template messages*(locale:string, body:untyped):untyped =
    ## Define the localisations for some messages
    ## TODO: show example
    static:
      if not locale_messages.hasKey(locale):
        locale_messages[locale] = newSeq[LocaleMessage]()

    var values {.compileTime, genSym.} = newTable[string,NimNode]()
    block:
      static:
        proc word(status:MessageStatus, hashval:int, key:string, value:NimNode) {.compileTime.} =
          if status != Gone:
            values[key] = value.copyNimTree()
          locale_messages[locale].add((
            status: status,
            hashval: hashval,
            key: key,
            value: value,
          ))

        macro todo(hashval:int, key:string, node:untyped):untyped {.used.} =
          word(Todo, hashval.intVal().int, $key, node)
        macro done(hashval:int, key:string, node:untyped):untyped {.used.} =
          word(Done, hashval.intVal().int, $key, node)
        macro redo(hashval:int, key:string, node:untyped):untyped {.used.} =
          word(Redo, hashval.intVal().int, $key, node)
        macro gone(hashval:int, key:string, node:untyped):untyped {.used.} =
          word(Gone, hashval.intVal().int, $key, node)
        body
    
    macro mkMessageGenerator():untyped {.genSym.} =
      ## Generate a proc that will return a Messages_CATALOGNAME
      ## filled with the messages for this locale and add it
      ## to the localeChoosers table
      var paramTree = nnkTupleConstr.newTree()
      for k,dftval in base_message_tab.pairs:
        let node = values.getOrDefault(k, dftval)
        paramTree.add(node.makeIntoClosure())

      result = nnkStmtList.newTree(
        nnkAsgn.newTree(
          nnkBracketExpr.newTree(
            newIdentNode(chooser_table_varname),
            newLit(locale)
          ),
          nnkLambda.newTree(
            newEmptyNode(),
            newEmptyNode(),
            newEmptyNode(),
            nnkFormalParams.newTree(
              newIdentNode(message_type_name)
            ),
            newEmptyNode(),
            newEmptyNode(),
            nnkStmtList.newTree(
              paramTree,
            )
          )
        )
      )
    mkMessageGenerator()


when isMainModule:
  import strutils
  import sequtils
  let cmd = paramStr(1)
  case cmd
  of "init":
    let transdir = "."/"trans"
    if transdir.existsDir:
      echo "Error: directory " & transdir & " already exists"
      quit(1)
    transdir.createDir()
    let base_nim = transdir / "base.nim"
    let all_nim = transdir / "all.nim"

    echo "Writing " & base_nim
    writeFile(base_nim, dedent"""
    import intl
    export intl
    
    intlCatalog "myproject"
    baseMessages:
      discard
    """)
    
    echo "Writing " & all_nim
    writeFile(all_nim, dedent"""
    import intl
    import ./base
    
    export intl
    export base
    """)
    
    echo dedent"""
    Next steps:
    
    1. Add this to any Nim files you want to localize:

      import ./trans/all
    
    2. At the end of your main Nim file add the following:

      import ./trans/all
      intlPostlude(currentSourcePath(), "trans")
    
    3. Add locales from the command-line with this command:

      $ intl add LOCALENAME
    """
  of "add":
    let transdir = "."/"trans"
    let locale = paramStr(2)
    let locale_file = transdir / locale & ".nim"
    if not locale_file.existsFile:
      writeFile(locale_file, dedent("""
      import ./base

      messages """ & '"' & locale & '"' & """:
        discard
      """))
      echo "Created " & locale_file
    else:
      echo "Error: file " & locale_file & " already exists"
      quit(1)
  else:
    echo "unknown command: " & cmd
    quit(1)

