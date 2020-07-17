type
  Messages* = ref object of RootObj
    s_hello*: string

proc getMessages*():Messages =
  Messages(
    s_hello: "hello"
  )
