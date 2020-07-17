import intl
import tables
import macros

intlDomain("MyThing")

baseMessages:
  msg "s_rhello4117552498", r"hello"
  msg "greeting", "salutations!"
  msg "s_rsomethin2855449644", r"something, big and scary!"
  msg "dogs", proc (count: int): string =
    "puppies"

messages "en":
  todo 28103, "Hello", "Hello"
  done 20392, "something", "amazing"
  todo 93994, "foobar", "foobar"
  done 65221, "greeting", "hummidahummida"
  ## foobar
  gone 12345, "yupper", "yep"

messages "es":
  todo 23802, "Hello", "Hola"


messages "fr":
  discard
