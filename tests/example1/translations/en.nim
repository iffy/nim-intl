import ./base

type
  EnMessages* = ref object of Messages

proc getMessages*():EnMessages =
  EnMessages(
    s_hello: "hello"
  )
