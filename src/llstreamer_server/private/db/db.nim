import std/[asyncdispatch, options]
import ".."/[exceptions, idgen]
import objects, sqlite

var conf: DatabaseConfig
var isSqlite = false
var isPostgres = false
var isMySql = false
proc initDb*(config: DatabaseConfig) =
    conf = config
    
    case conf.kind:
    of DatabaseConfigKind.Memory:
        isSqlite = true
        initSqlite(":memory:", conf.useQueryThread)
    of DatabaseConfigKind.Sqlite:
        isSqlite = true
        initSqlite(conf.sqliteDbPath, true)
    of DatabaseConfigKind.Postgres:
        isPostgres = true
        raise newException(DatabaseError, "PostgreSQL support not yet implemented")
    of DatabaseConfigKind.MySql:
        isMySql = true
        raise newException(DatabaseError, "MySQL support not yet implemented")

# Abstracted database procs

proc insertAccount*(username: string, passwordHash: string, metadata: Option[Metadata], isEphemeral: bool): Future[AccountRow] =
    ## Inserts a new account with the specified details and returns it.
    ## In most cases you should use "createAccount" in the "accounts" module, because it hashes the password and does other important things.
    ## This method simply creates an entry in the database.
    
    if isSqlite:
        return sqlite.insertAccount(username, passwordHash, metadata, isEphemeral)
    elif isPostgres:
        raise newException(DatabaseError, "PostgreSQL support not yet implemented")
    elif isMySql:
        raise newException(DatabaseError, "MySQL support not yet implemented")

proc fetchAccountById*(id: AccountId): Future[Option[AccountRow]] =
    ## Fetches an account by its ID, returning none if none with the specified ID exist.
    
    if isSqlite:
        return sqlite.fetchAccountById(id)
    elif isPostgres:
        raise newException(DatabaseError, "PostgreSQL support not yet implemented")
    elif isMySql:
        raise newException(DatabaseError, "MySQL support not yet implemented")

proc fetchAccountByUsername*(username: string): Future[Option[AccountRow]] =
    ## Fetches an account by its username, returning none if none with the specified username exists.
    
    if isSqlite:
        return sqlite.fetchAccountByUsername(username)
    elif isPostgres:
        raise newException(DatabaseError, "PostgreSQL support not yet implemented")
    elif isMySql:
        raise newException(DatabaseError, "MySQL support not yet implemented")