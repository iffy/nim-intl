import ./base

type
  EsMessages* = ref object of Messages

proc getMessages*():EsMessages =
  EsMessages(
    s_hello: "hola"
  )
