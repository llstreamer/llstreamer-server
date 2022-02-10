import std/[tables, options]
import ".."/[idgen, utils]

type
    Metadata* = Table[string, string]

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
    
    DatabaseConfigKind* {.pure.} = enum
        Memory
        Sqlite
        Postgres
        MySql

    DatabaseConfig* = object
        case kind*: DatabaseConfigKind
        of DatabaseConfigKind.Memory:
            useQueryThread*: bool
        of DatabaseConfigKind.Sqlite:
            sqliteDbPath*: string
        of DatabaseConfigKind.Postgres:
            pgDb*: string
            pgAddress*: string
            pgPort*: Natural
            pgUser*: string
            pgPass*: string
            pgPoolSize*: Natural
        of DatabaseConfigKind.MySql:
            mysqlDb*: string
            mysqlAddress*: string
            mysqlPort*: Natural
            mysqlUser*: string
            mysqlPass*: string
            mysqlPoolSize*: Natural