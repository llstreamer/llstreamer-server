import std/[options]
import ".."/[idgen, utils, objects]

type
    AccountRow* = object
        id*: AccountId
        username*: string
        passwordHash*: string
        metadata*: Option[Metadata]
        isEphemeral*: bool
        creationDate*: EpochSecond
    
    StreamRow* = object
        id*: StreamId
        owner*: AccountId
        name*: string
        isPublished*: bool
        key*: string
        custodianKey*: string
        metadata*: Option[Metadata]
        creationDate*: EpochSecond