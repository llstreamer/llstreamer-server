import std/[tables]

type
    Metadata* = Table[string, string]
        ## Metadata stored in database and sent in packets (for accounts, streams, etc)