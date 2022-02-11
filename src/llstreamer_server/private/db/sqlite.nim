import std/[db_sqlite, locks, asyncdispatch, tables, os, strformat, options, times, strutils, sequtils, algorithm, sugar]
import msgpack4nim
import ".."/[logging, exceptions, utils, idgen]
import objects, migrations

type
    QueryKind {.pure.} = enum
        Exec,
        Rows,
        Row,
        Value

    Query = object
        sql: SqlPrepared

        case kind: QueryKind
        of QueryKind.Exec:
            execFuture: Future[void]
        of QueryKind.Rows:
            rowsFuture: Future[seq[seq[string]]]
        of QueryKind.Row:
            rowFuture: Future[seq[string]]
        of QueryKind.Value:
            valueFuture: Future[string]
    
    QueryQueue = object
        lock: Lock
        queries: seq[Query]
    
    Sqlite = object
        lock: Lock
        conn: DbConn
        useThread: bool

var sqlite: Sqlite
var queryQueue: QueryQueue

var sqliteThread: Thread[tuple[db: ptr Sqlite, queue: ptr QueryQueue]]
proc sqliteThreadProc(args: tuple[db: ptr Sqlite, queue: ptr QueryQueue]) {.thread.} =
    let db = args.db
    let queue = args.queue

    proc fail[T](future: Future[T], queryKind: QueryKind, ex: ref Exception, exMsg: string) =
        logError fmt"Failed to run SQLite query of type {queryKind}", ex, exMsg
        future.fail(ex)

    while true:
        sleep(5)

        # Check if there are any new queries in the queue
        while queue[].queries.len > 0:
            var query: Query
            withLock queue[].lock:
                query = queue[].queries[0]
                queue[].queries.del(0)

            withLock db[].lock:
                case query.kind:
                of QueryKind.Exec:
                    try:
                        db[].conn.exec(query.sql)
                        query.execFuture.complete()
                    except:
                        query.execFuture.fail(query.kind, getCurrentException(), getCurrentExceptionMsg())
                of QueryKind.Rows:
                    try:
                        let res = db[].conn.getAllRows(query.sql)
                        query.rowsFuture.complete(res)
                    except:
                        query.rowsFuture.fail(query.kind, getCurrentException(), getCurrentExceptionMsg())
                of QueryKind.Row:
                    try:
                        let res = db[].conn.getAllRows(query.sql)[0]
                        query.rowFuture.complete(res)
                    except:
                        query.rowFuture.fail(query.kind, getCurrentException(), getCurrentExceptionMsg())
                of QueryKind.Value:
                    try:
                        let res = db[].conn.getValue(query.sql)
                        query.valueFuture.complete(res)
                    except:
                        query.valueFuture.fail(query.kind, getCurrentException(), getCurrentExceptionMsg())
                
                # Destroy statement
                finalize(query.sql)

proc initSqlite*(filePath: string, useThread: bool) =
    ## Initializes the SQLite database connection and worker thread

    sqlite.conn = open(filePath, "", "", "")
    sqlite.conn.applyMigrations()
    sqlite.useThread = useThread
    if useThread:
        queryQueue.queries = newSeq[Query]()
        createThread(sqliteThread, sqliteThreadProc, (addr sqlite, addr queryQueue))

proc timestampToEpochSecond(timestamp: string): EpochSecond =
    return (uint64) parseTime(timestamp, "yyyy-MM-dd HH:mm:ss", utc()).toUnix()

proc exec(sql: SqlPrepared): Future[void] {.async.} =
    ## Executes an SQLite statement

    if sqlite.useThread:
        let future = newFuture[void]("sqlite.exec")
        withLock queryQueue.lock:
            queryQueue.queries.add(Query(
                sql: sql,
                kind: QueryKind.Exec,
                execFuture: future
            ))
        await future
    else:
        withLock sqlite.lock:
            sqlite.conn.exec(sql)

proc getAllRows(sql: SqlPrepared): Future[seq[seq[string]]] {.async.} =
    ## Executes an SQLite query and returns all rows in a raw format

    if sqlite.useThread:
        let future = newFuture[seq[seq[string]]]("sqlite.getAllRows")
        withLock queryQueue.lock:
            queryQueue.queries.add(Query(
                sql: sql,
                kind: QueryKind.Rows,
                rowsFuture: future
            ))
        return await future
    else:
        withLock sqlite.lock:
            return sqlite.conn.getAllRows(sql)

proc getRow(sql: SqlPrepared): Future[seq[string]] {.async.} =
    ## Executes an SQLite query and returns the first row

    if sqlite.useThread:
        let future = newFuture[seq[string]]("sqlite.getRow")
        withLock queryQueue.lock:
            queryQueue.queries.add(Query(
                sql: sql,
                kind: QueryKind.Row,
                rowFuture: future
            ))
        return await future
    else:
        withLock sqlite.lock:
            return sqlite.conn.getAllRows(sql)[0]

proc getValue(sql: SqlPrepared): Future[string] {.async.} =
    ## Executes an SQLite query and returns the first value in the first row

    if sqlite.useThread:
        let future = newFuture[string]("sqlite.getRow")
        withLock queryQueue.lock:
            queryQueue.queries.add(Query(
                sql: sql,
                kind: QueryKind.Value,
                valueFuture: future
            ))
        return await future
    else:
        withLock sqlite.lock:
            return sqlite.conn.getValue(sql)

proc parseAccountRow(row: seq[string]): AccountRow =
    # Parse row
    let rowId = (AccountId) parseInt(row[0])
    let rowUsername = row[1]
    let rowPass = row[2]
    let rowMetaRaw = row[3]
    var rowMeta = none[Metadata]()
    if rowMetaRaw.len > 0:
        rowMeta = some(rowMetaRaw.unpack(Metadata))
    let rowEphemeral = row[4] == "true"
    let rowDate = timestampToEpochSecond(row[5])

    # Return it
    return AccountRow(
        id: rowId,
        username: rowUsername,
        passwordHash: rowPass,
        metadata: rowMeta,
        isEphemeral: rowEphemeral,
        creationDate: rowDate
    )

proc parseAccountRowOrNone(row: seq[string]): Option[AccountRow] =
    # Check if row is empty
    if row[0].len > 0:
        return some(parseAccountRow(row))
    else:
        return none[AccountRow]()

proc parseStreamRow(row: seq[string]): StreamRow =
    # Parse row
    let rowId = (StreamId) parseInt(row[0])
    let rowOwner = (AccountId) parseInt(row[1])
    let rowName = row[2]
    let rowPublished = row[3] == "true"
    let rowKey = row[4]
    let rowCustKey = row[5]
    let rowMetaRaw = row[6]
    var rowMeta = none[Metadata]()
    if rowMetaRaw.len > 0:
        rowMeta = some(rowMetaRaw.unpack(Metadata))
    let rowDate = timestampToEpochSecond(row[7])

    # Return it
    return StreamRow(
        id: rowId,
        owner: rowOwner,
        name: rowName,
        isPublished: rowPublished,
        key: rowKey,
        custodianKey: rowCustKey,
        metadata: rowMeta,
        creationDate: rowDate
    )

proc parseStreamRowOrNone(row: seq[string]): Option[StreamRow] =
    # Check if row is empty
    if row[0].len > 0:
        return some(parseStreamRow(row))
    else:
        return none[StreamRow]()

proc insertAccount*(username: string, passwordHash: string, metadata: Option[Metadata], isEphemeral: bool): Future[AccountRow] {.async.} =
    ## Inserts a new account with the specified details and returns it.
    ## In most cases you should use "createAccount" in the "accounts" module, because it hashes the password and does other important things.
    ## This method simply creates an entry in the database.

    # Prepare statement and serialize metadata
    let stmt = sqlite.conn.prepare("""
    INSERT INTO accounts
    (account_username, account_password_hash, account_metadata, account_ephemeral)
    VALUES
    (?, ?, ?, ?)
    RETURNING *
    """)
    stmt.bindParam(1, username)
    stmt.bindParam(2, passwordHash)
    if metadata.isSome:
        stmt.bindParam(3, cast[seq[uint8]](metadata.get.pack()))
    else:
        stmt.bindNull(3)
    stmt.bindParam(4, (int) isEphemeral)
    
    # Insert values and return row
    return parseAccountRow(await getRow(stmt))

proc fetchAccountById*(id: AccountId): Future[Option[AccountRow]] {.async.} =
    ## Fetches an account by its ID, returning none if none with the specified ID exist.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("SELECT * FROM accounts WHERE id = ? LIMIT 1")
    stmt.bindParams((int64) id)

    # Fetch account
    let row = await getRow(stmt)

    # Return parsed row or lack of one
    return parseAccountRowOrNone(row)

proc fetchAccountByUsername*(username: string): Future[Option[AccountRow]] {.async.} =
    ## Fetches an account by its username, returning none if none with the specified username exists.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("SELECT * FROM accounts WHERE account_username = ? LIMIT 1")
    stmt.bindParams(username)

    # Fetch account
    let row = await getRow(stmt)

    # Return parsed row or lack of one
    return parseAccountRowOrNone(row)

proc updateAccountMetadataById*(id: AccountId, metadata: Option[Metadata]) {.async.} =
    ## Updates the metadata of the account with the specified ID if it exists.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("UPDATE accounts SET account_metadata = ? WHERE id = ? LIMIT 1")
    if metadata.isSome:
        stmt.bindParam(1, cast[seq[uint8]](metadata.get.pack()))
    else:
        stmt.bindNull(1)
    stmt.bindParam(2, (int64) id)

    # Execute
    await exec(stmt)

proc updateAccountMetadataByUsername*(username: string, metadata: Option[Metadata]) {.async.} =
    ## Updates the metadata of the account with the specified username if it exists.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("UPDATE accounts SET account_metadata = ? WHERE account_username = ? LIMIT 1")
    if metadata.isSome:
        stmt.bindParam(1, cast[seq[uint8]](metadata.get.pack()))
    else:
        stmt.bindNull(1)
    stmt.bindParam(2, username)

    # Execute
    await exec(stmt)

proc deleteAccountById*(id: AccountId) {.async.} =
    ## Deletes the account with the specified ID if it exists.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("DELETE accounts WHERE id = ? LIMIT 1")
    stmt.bindParams((int64) id)

    # Execute
    await exec(stmt)

proc deleteAccountByUsername*(username: string) {.async.} =
    ## Deletes the account with the specified username if it exists.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("DELETE accounts account_username = ? LIMIT 1")
    stmt.bindParams(username)

    # Execute
    await exec(stmt)

proc insertStream*(ownerId: AccountId, name: string, isPublished: bool, key: string, custodianKey: string, metadata: Option[Metadata]): Future[StreamRow] {.async.} =
    ## Inserts a new stream with the specified details and returns it.
    ## In most cases you should use "createStream" in the "streams" module, because it handles key generation and does other important things.
    ## This method simply creates an entry in the database.

    # Prepare statement and serialize metadata
    let stmt = sqlite.conn.prepare("""
    INSERT INTO streams
    (stream_owner, stream_name, stream_published, stream_key, stream_custodian_key, stream_metadata)
    VALUES
    (?, ?, ?, ?, ?, ?)
    RETURNING *
    """)
    stmt.bindParam(1, (int64) ownerId)
    stmt.bindParam(2, name)
    stmt.bindParam(3, (int) isPublished)
    stmt.bindParam(4, key)
    stmt.bindParam(5, custodianKey)
    if metadata.isSome:
        stmt.bindParam(6, cast[seq[uint8]](metadata.get.pack()))
    else:
        stmt.bindNull(6)
    
    # Insert values and return row
    return parseStreamRow(await getRow(stmt))

proc fetchStreamById*(id: StreamId): Future[Option[StreamRow]] {.async.} =
    ## Fetches a stream by its ID, returning none if none with the specified ID exist.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("SELECT * FROM streams WHERE id = ? LIMIT 1")
    stmt.bindParams((int64) id)

    # Fetch stream
    let row = await getRow(stmt)

    # Return parsed row or lack of one
    return parseStreamRowOrNone(row)

proc fetchStreamsByOwner*(ownerId: AccountId): Future[seq[StreamRow]] {.async.} =
    ## Fetches all streams by the specified owner
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("SELECT * FROM streams WHERE stream_owner = ?")
    stmt.bindParams((int64) ownerId)

    # Fetch stream
    let rows = await getAllRows(stmt)

    # Return parsed rows
    return rows.map(row => parseStreamRow(row))

proc fetchPublicStreamsAfter*(id: StreamId, limit: int): Future[seq[StreamRow]] {.async.} =
    ## Fetches public streams with an ID higher the specified ID, returning a maximum of the specified amount.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("""
    SELECT * FROM streams
    WHERE stream_published = TRUE AND id > ?
    ORDER BY id ASC
    LIMIT ?
    """)
    stmt.bindParams((int64) id, limit)

    # Fetch 
    let rows = await getAllRows(stmt)

    # Return parsed rows
    return rows.map(row => parseStreamRow(row))

proc fetchPublicStreamsBefore*(id: StreamId, limit: int): Future[seq[StreamRow]] {.async.} =
    ## Fetches public streams with an ID higher the specified ID, returning a maximum of the specified amount (ordered by ID descending and then reversed after fetch, to facilitate pagination).
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("""
    SELECT * FROM streams
    WHERE stream_published = TRUE AND id < ?
    ORDER BY id DESC
    LIMIT ?
    """)
    stmt.bindParams((int64) id, limit)

    # Fetch 
    let rows = await getAllRows(stmt)

    # Parse and reverse rows
    var parsed = rows.map(row => parseStreamRow(row))
    parsed.reverse()

    # Return parsed rows
    return parsed

proc updateStreamMetadataById*(id: StreamId, metadata: Option[Metadata]) {.async.} =
    ## Updates the metadata of the stream with the specified ID if it exists.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("UPDATE streams SET stream_metadata = ? WHERE id = ? LIMIT 1")
    if metadata.isSome:
        stmt.bindParam(1, cast[seq[uint8]](metadata.get.pack()))
    else:
        stmt.bindNull(1)
    stmt.bindParam(2, (int64) id)

    # Execute
    await exec(stmt)

proc updateStreamNameById*(id: StreamId, name: string) {.async.} =
    ## Updates the name of the stream with the specified ID if it exists.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("UPDATE steams SET stream_name = ? WHERE id = ? LIMIT 1")
    stmt.bindParams(name, (int64) id)

    # Execute
    await exec(stmt)

proc deleteStreamById*(id: AccountId) {.async.} =
    ## Deletes the stream with the specified ID if it exists.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("DELETE streams WHERE id = ? LIMIT 1")
    stmt.bindParams((int64) id)

    # Execute
    await exec(stmt)

proc deleteStreamsByOwner*(ownerId: AccountId) {.async.} =
    ## Deletes all streams with the specified owner.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("DELETE streams WHERE stream_owner = ?")
    stmt.bindParams((int64) ownerId)

    # Execute
    await exec(stmt)