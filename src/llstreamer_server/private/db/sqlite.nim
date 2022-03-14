import std/[db_sqlite, locks, asyncdispatch, tables, os, strformat, options, times, strutils, sequtils, algorithm, sugar]
import msgpack4nim
import ".."/[logging, exceptions, utils, idgen, simpletypes, threadutils]
import objects as db_objects
import migrations

type
    QueryKind {.pure.} = enum
        Exec,
        Rows,
        Row,
        Value

    Query = object
        id: uint32
        sql: SqlPrepared

        kind: QueryKind
    
    QueryRes = object
        id: uint32
        error: Option[ref Exception]
        case kind: QueryKind:
        of QueryKind.Exec:
            ## No result
        of QueryKind.Rows:
            rowsRes: seq[seq[string]]
        of QueryKind.Row:
            rowRes: Option[seq[string]]
        of QueryKind.Value:
            valueRes: Option[string]
    
    QueryFut = object
        case kind: QueryKind
        of QueryKind.Exec:
            execFut: Future[void]
        of QueryKind.Rows:
            rowsFut: Future[seq[Row]]
        of QueryKind.Row:
            rowFut: Future[Option[Row]]
        of QueryKind.Value:
            valueFut: Future[Option[string]]
    
    Sqlite = object
        lock: Lock
        conn: DbConn
        useThread: bool

# Query ID generation
var id = (uint32) 0;
proc genId(): uint32 =
    inc id
    return id

# SQLite connection reference
var sqlite = new (ref Sqlite)

# Channels for passing queries/results to/from the worker thread
var queryChan: ptr Channel[Query]
var resChan: ptr Channel[QueryRes]

# Table of query IDs and their corresponding Futures
var futsTable = new Table[uint32, QueryFut]

var sqliteThread: Thread[(ref Sqlite, ptr Channel[Query], ptr Channel[QueryRes])]
proc sqliteThreadProc(args: (ref Sqlite, ptr Channel[Query], ptr Channel[QueryRes])) {.thread.} =
    let db = args[0]
    let queries = args[1]
    let res = args[2]

    proc fail(query: Query, ex: ref Exception, exMsg: string) =
        logError fmt"Failed to run SQLite query of type {query.kind}", ex, exMsg
        res[].send(QueryRes(
            id: query.id,
            error: some(ex),
            kind: query.kind
        ))

    while true:
        sleep(1)

        # Check if there are any new queries in the channel
        let queryRes = queries[].tryRecv()
        if queryRes.dataAvailable:
            let query = queryRes.msg

            # Handle the query according to its type
            withLock db.lock:
                case query.kind:
                of QueryKind.Exec:
                    try:
                        db.conn.exec(query.sql)
                        
                        # Send result
                        res[].send(QueryRes(
                            id: query.id,
                            error: none[ref Exception](),
                            kind: QueryKind.Exec
                        ))
                    except:
                        query.fail(getCurrentException(), getCurrentExceptionMsg())
                of QueryKind.Rows:
                    try:
                        let dbRes = db.conn.getAllRows(query.sql)
                        
                        # Send result
                        res[].send(QueryRes(
                            id: query.id,
                            error: none[ref Exception](),
                            kind: QueryKind.Rows,
                            rowsRes: dbRes
                        ))
                    except:
                        query.fail(getCurrentException(), getCurrentExceptionMsg())
                of QueryKind.Row:
                    try:
                        let dbRes = db.conn.getAllRows(query.sql)
                        var val: Option[Row]
                        if dbRes.len > 0:
                            val = some(dbRes[0])
                        else:
                            val = none[Row]()
                        
                        # Send result
                        res[].send(QueryRes(
                            id: query.id,
                            error: none[ref Exception](),
                            kind: QueryKind.Row,
                            rowRes: val
                        ))
                    except:
                        query.fail(getCurrentException(), getCurrentExceptionMsg())
                of QueryKind.Value:
                    try:
                        let dbRes = db.conn.getAllRows(query.sql)
                        var val: Option[string]
                        if dbRes.len > 0 and dbRes[0].len > 0:
                            val = some(dbRes[0][0])
                        else:
                            val  = none[string]()
                        
                        # Send result
                        res[].send(QueryRes(
                            id: query.id,
                            error: none[ref Exception](),
                            kind: QueryKind.Value,
                            valueRes: val
                        ))
                    except:
                        query.fail(getCurrentException(), getCurrentExceptionMsg())
                
                # Destroy statement
                finalize(query.sql)

proc resRecvLoop() {.async.} =
    ## Loop that checks for results and completes their corresponding futures

    while true:
        await sleepAsync(1)

        # Check for result
        let resRes = resChan[].tryRecv()
        if resRes.dataAvailable:
            let res = resRes.msg

            # Check for key in futures table
            if futsTable.hasKey(res.id):
                let val = futsTable[res.id]
                futsTable.del(res.id)

                # Fail future if error present, otherwise complete it
                if res.error.isSome:
                    case res.kind:
                    of QueryKind.Exec:
                        val.execFut.fail(res.error.get)
                    of QueryKind.Rows:
                        val.rowsFut.fail(res.error.get)
                    of QueryKind.Row:
                        val.rowFut.fail(res.error.get)
                    of QueryKind.Value:
                        val.valueFut.fail(res.error.get)
                else:
                    case res.kind:
                    of QueryKind.Exec:
                        val.execFut.complete()
                    of QueryKind.Rows:
                        val.rowsFut.complete(res.rowsRes)
                    of QueryKind.Row:
                        val.rowFut.complete(res.rowRes)
                    of QueryKind.Value:
                        val.valueFut.complete(res.valueRes)

proc initSqlite*(filePath: string, useThread: bool) =
    ## Initializes the SQLite database connection, worker thread, and related components

    # Open database
    sqlite.conn = open(filePath, "", "", "")
    sqlite.conn.applyMigrations()
    sqlite.useThread = useThread

    # Start thread if enabled
    if useThread:
        # Allocate shared memory for channels
        queryChan = cast[ptr Channel[Query]](
            allocShared0(sizeof(Channel[Query]))
        )
        resChan = cast[ptr Channel[QueryRes]](
            allocShared0(sizeof(Channel[QueryRes]))
        )
        queryChan[].open()
        resChan[].open()

        # Start result receiver and worker thread
        asyncCheck resRecvLoop()
        createThread(sqliteThread, sqliteThreadProc, (sqlite, queryChan, resChan))

proc timestampToEpochSecond(timestamp: string): EpochSecond =
    return (uint64) parseTime(timestamp, "yyyy-MM-dd HH:mm:ss", utc()).toUnix()

proc exec(sql: SqlPrepared): Future[void] =
    ## Executes an SQLite statement
    
    let future = newFuture[void]("sqlite.exec")

    if sqlite.useThread:
        # Generate ID and insert future into futures table
        let id = genId()
        futsTable[id] = QueryFut(
            kind: QueryKind.Exec,
            execFut: future
        )

        # Send query
        queryChan[].send(Query(
            id: id,
            sql: sql,
            kind: QueryKind.Exec
        ))
    else:
        withLock sqlite.lock:
            sqlite.conn.exec(sql)
            future.complete()
    
    return future

proc getAllRows(sql: SqlPrepared): Future[seq[Row]] =
    ## Executes an SQLite query and returns all rows in a raw format
    
    let future = newFuture[seq[Row]]("sqlite.getAllRows")

    if sqlite.useThread:
        # Generate ID and insert future into futures table
        let id = genId()
        futsTable[id] = QueryFut(
            kind: QueryKind.Rows,
            rowsFut: future
        )

        # Send query
        queryChan[].send(Query(
            id: id,
            sql: sql,
            kind: QueryKind.Rows
        ))
    else:
        withLock sqlite.lock:
            future.complete(sqlite.conn.getAllRows(sql))
    
    return future

proc getRow(sql: SqlPrepared): Future[Option[Row]] =
    ## Executes an SQLite query and returns the first row

    let future = newFuture[Option[Row]]("sqlite.getRow")

    if sqlite.useThread:
        # Generate ID and insert future into futures table
        let id = genId()
        futsTable[id] = QueryFut(
            kind: QueryKind.Row,
            rowFut: future
        )

        # Send query
        queryChan[].send(Query(
            id: id,
            sql: sql,
            kind: QueryKind.Row
        ))
    else:
        withLock sqlite.lock:
            let res = sqlite.conn.getAllRows(sql)
            if res.len > 0:
                future.complete(some(res[0]))
            else:
                future.complete(none[Row]())
    
    return future

proc getValue(sql: SqlPrepared): Future[Option[string]] =
    ## Executes an SQLite query and returns the first value in the first row

    let future = newFuture[Option[string]]("sqlite.getValue")

    if sqlite.useThread:
        # Generate ID and insert future into futures table
        let id = genId()
        futsTable[id] = QueryFut(
            kind: QueryKind.Value,
            valueFut: future
        )

        # Send query
        queryChan[].send(Query(
            id: id,
            sql: sql,
            kind: QueryKind.Value
        ))
    else:
        withLock sqlite.lock:
            let res = sqlite.conn.getAllRows(sql)
            if res.len > 0 and res[0].len > 0:
                future.complete(some(res[0][0]))
            else:
                future.complete(none[string]())
    
    return future

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

proc parseAccountRowOrNone(row: Option[seq[string]]): Option[AccountRow] =
    # Check if row is empty
    if row.isSome:
        return some(parseAccountRow(row.get))
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

proc parseStreamRowOrNone(row: Option[seq[string]]): Option[StreamRow] =
    # Check if row is empty
    if row.isSome:
        return some(parseStreamRow(row.get))
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
    return parseAccountRow((await getRow(stmt)).get)

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
    let stmt = sqlite.conn.prepare("DELETE FROM accounts WHERE id = ? LIMIT 1")
    stmt.bindParams((int64) id)

    # Execute
    await exec(stmt)

proc deleteAccountByUsername*(username: string) {.async.} =
    ## Deletes the account with the specified username if it exists.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("DELETE FROM accounts WHERE account_username = ? LIMIT 1")
    stmt.bindParams(username)

    # Execute
    await exec(stmt)

proc deleteEphemeralAccounts*() {.async.} =
    ## Deletes all accounts that are marked as ephemeral
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("DELETE FROM accounts WHERE account_ephemeral IS TRUE")
    
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
    return parseStreamRow((await getRow(stmt)).get)

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
    let stmt = sqlite.conn.prepare("DELETE FROM streams WHERE id = ? LIMIT 1")
    stmt.bindParams((int64) id)

    # Execute
    await exec(stmt)

proc deleteStreamsByOwner*(ownerId: AccountId) {.async.} =
    ## Deletes all streams with the specified owner.
    
    # Prepare statement
    let stmt = sqlite.conn.prepare("DELETE FROM streams WHERE stream_owner = ?")
    stmt.bindParams((int64) ownerId)

    # Execute
    await exec(stmt)