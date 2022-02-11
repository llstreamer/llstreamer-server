import std/[asyncfutures, options]
import ".."/[exceptions, idgen]
import objects, sqlite

var conf: DatabaseConfig
var isSqlite = false
var isPostgres = false
var isMySql = false
proc initDb*(config: DatabaseConfig) {.raises: DatabaseError.} =
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
        raise newDatabaseError("PostgreSQL support not yet implemented")
    of DatabaseConfigKind.MySql:
        isMySql = true
        raise newDatabaseError("MySQL support not yet implemented")

# Abstracted database procs

proc insertAccount*(username: string, passwordHash: string, metadata: Option[Metadata], isEphemeral: bool): Future[AccountRow] {.raises: DatabaseError.} =
    ## Inserts a new account with the specified details and returns it.
    ## In most cases you should use "createAccount" in the "accounts" module, because it hashes the password and does other important things.
    ## This method simply creates an entry in the database.
    
    if isSqlite:
        return sqlite.insertAccount(username, passwordHash, metadata, isEphemeral)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc fetchAccountById*(id: AccountId): Future[Option[AccountRow]] {.raises: DatabaseError.} =
    ## Fetches an account by its ID, returning none if none with the specified ID exist.
    
    if isSqlite:
        return sqlite.fetchAccountById(id)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc fetchAccountByUsername*(username: string): Future[Option[AccountRow]] {.raises: DatabaseError.} =
    ## Fetches an account by its username, returning none if none with the specified username exists.
    
    if isSqlite:
        return sqlite.fetchAccountByUsername(username)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc updateAccountMetadataById*(id: AccountId, metadata: Option[Metadata]): Future[void] {.raises: DatabaseError.} =
    ## Updates the metadata of the account with the specified ID if it exists.
    
    if isSqlite:
        return sqlite.updateAccountMetadataById(id, metadata)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc updateAccountMetadataByUsername*(username: string, metadata: Option[Metadata]): Future[void] {.raises: DatabaseError.} =
    ## Updates the metadata of the account with the specified username if it exists.
    
    if isSqlite:
        return sqlite.updateAccountMetadataByUsername(username, metadata)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc deleteAccountById*(id: AccountId): Future[void] {.raises: DatabaseError.} =
    ## Deletes the account with the specified ID if it exists.
    
    if isSqlite:
        return sqlite.deleteAccountById(id)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc deleteAccountByUsername*(username: string): Future[void] {.raises: DatabaseError.} =
    ## Deletes the account with the specified username if it exists.
    
    if isSqlite:
        return sqlite.deleteAccountByUsername(username)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc insertStream*(ownerId: AccountId, name: string, isPublished: bool, key: string, custodianKey: string, metadata: Option[Metadata]): Future[StreamRow] {.raises: DatabaseError.} =
    ## Inserts a new stream with the specified details and returns it.
    ## In most cases you should use "createStream" in the "streams" module, because it handles key generation and does other important things.
    ## This method simply creates an entry in the database.

    if isSqlite:
        return sqlite.insertStream(ownerId, name, isPublished, key, custodianKey, metadata)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc fetchStreamById*(id: StreamId): Future[Option[StreamRow]] {.raises: DatabaseError.} =
    ## Fetches a stream by its ID, returning none if none with the specified ID exist.
    
    if isSqlite:
        return sqlite.fetchStreamById(id)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc fetchStreamsByOwner*(ownerId: AccountId): Future[seq[StreamRow]] {.raises: DatabaseError.} =
    ## Fetches all streams by the specified owner
    
    if isSqlite:
        return sqlite.fetchStreamsByOwner(ownerId)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc fetchPublicStreamsAfter*(id: StreamId, limit: int): Future[seq[StreamRow]] {.raises: DatabaseError.} =
    ## Fetches public streams with an ID higher the specified ID, returning a maximum of the specified amount.
    
    if isSqlite:
        return sqlite.fetchPublicStreamsAfter(id, limit)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc fetchPublicStreamsBefore*(id: StreamId, limit: int): Future[seq[StreamRow]] {.raises: DatabaseError.} =
    ## Fetches public streams with an ID higher the specified ID, returning a maximum of the specified amount (ordered by ID descending and then reversed after fetch, to facilitate pagination).
    
    if isSqlite:
        return sqlite.fetchPublicStreamsBefore(id, limit)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc updateStreamMetadataById*(id: StreamId, metadata: Option[Metadata]): Future[void] {.raises: DatabaseError.} =
    ## Updates the metadata of the stream with the specified ID if it exists.
    
    if isSqlite:
        return sqlite.updateStreamMetadataById(id, metadata)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc updateStreamNameById*(id: StreamId, name: string): Future[void] {.raises: DatabaseError.} =
    ## Updates the name of the stream with the specified ID if it exists.
    
    if isSqlite:
        return sqlite.updateStreamNameById(id, name)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc deleteStreamById*(id: AccountId): Future[void] {.raises: DatabaseError.} =
    ## Deletes the stream with the specified ID if it exists.
    
    if isSqlite:
        return sqlite.deleteStreamById(id)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")

proc deleteStreamsByOwner*(ownerId: AccountId): Future[void] {.raises: DatabaseError.} =
    ## Deletes all streams with the specified owner.
    
    if isSqlite:
        return sqlite.deleteStreamsByOwner(ownerId)
    elif isPostgres:
        raise newDatabaseError("PostgreSQL support not yet implemented")
    elif isMySql:
        raise newDatabaseError("MySQL support not yet implemented")