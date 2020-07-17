import unittest
import os
import osproc
import strutils
import strformat
import random
import times

import intl

randomize()

template withtmpdir(body:untyped):untyped =
  let tmpdir = getTempDir() / ($getTime().toUnix()) & $rand(10000)
  tmpdir.createDir()
  let olddir = getCurrentDir()
  setCurrentDir(tmpdir)
  checkpoint tmpdir
  try:
    body
  finally:
    setCurrentDir(olddir)

proc comp(filename:string, flags = ""):string =
  ## Compile the given nim file
  ## This is not safe to use outside of these tests
  let
    path = currentSourcePath().parentDir().parentDir()/"src"
    nimfile = filename.changeFileExt("nim")
  let compile_res = execCmdEx(&"nim c -r --hints:off --path:{path} {flags} {nimfile}", )
  echo compile_res.output
  assert compile_res.exitCode == 0
  result = compile_res.output

proc run(nimfile:string):string =
  ## Run an executable
  let exefile = nimfile.changeFileExt(ExeExt)
  let run_res = execCmdEx("."/exefile)
  result = run_res.output


test "import":
  checkpoint "import start checkpoint"
  withtmpdir:
    writeFile("src.nim", dedent"""
    import intl
    intlDomain "test"
    echo tr"foo"
    """)
    discard comp("src.nim")
    check run("./src.nim") == "foo\l"

test "managedir":
  withtmpdir:
    let trans_dir = absolutePath("."/"trans")
    writeFile("src.nim", dedent &"""
    import intl
    intlDomain "test"
    echo tr("hi","hi")
    intlPostlude(currentSourcePath(), autoDir="trans")
    """)
    discard comp("src.nim")
    assert existsDir("trans")

    let basefile = "trans"/"base.nim"
    assert existsFile(basefile)
    var basefileguts = basefile.readFile()
    checkpoint "=== " & basefile
    checkpoint basefileguts
    check "\"hi\"" in basefileguts
    check "intlDomain \"test\"" in basefileguts

    let allfile = "trans"/"all.nim"
    assert existsFile(allfile)
    var allfileguts = allfile.readFile()
    checkpoint "=== " & allfile
    checkpoint allfileguts
    check "import ./base" in allfileguts
    check "export base" in allfileguts
    check "import intl" in allfileguts
    check "export intl" in allfileguts

    # add some locales
    writeFile("src.nim", dedent &"""
    import ./trans/all
    echo tr("hi","hi")
    intlPostlude(currentSourcePath(), autoDir="trans")
    """)
    writeFile("trans"/"es.nim", "")
    writeFile("trans"/"en_GB.nim", "")
    writeFile("trans"/"en.nim", "")

    discard comp("src.nim")

    basefileguts = basefile.readFile()
    checkpoint "=== " & basefile
    checkpoint basefileguts
    check "intlDomain \"test\"" in basefileguts

    allfileguts = allfile.readFile()
    checkpoint "=== " & allfile
    checkpoint allfileguts
    check "import ./es" in allfileguts
    check "import ./en_GB" in allfileguts
    check "import ./en" in allfileguts

    var esguts = readFile("trans"/"es.nim")
    checkpoint "=== trans/es.nim"
    checkpoint esguts
    check "import ./base" in esguts
    check "messages \"es\":" in esguts
    check "todo" in esguts
    check "\"hi\"" in esguts

    # Does it still compile?
    discard comp("src.nim")

