import macros

import ./translations/all

proc showStrings() =
  echo "hello: ", tr"hello"
  echo "salut: ", tr("greeting", "salutations!!")
  echo "long:  ", tr"something, big and scary!"
  echo "dogs:  ", tr("dogs", proc(count:int):string = "puppies")(5)

showStrings()
var locale = "es"
setLocale(locale)
showStrings()

static: postlude()
