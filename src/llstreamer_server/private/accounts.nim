import std/[locks, tables, asyncdispatch, options]
import db/[db]
import db/objects as db_objects
import objects, idgen, client, crypto

type
    AccountsInUse = tuple[
        lock: Lock,
        accounts: Table[string, Account]
    ]

proc accRowToAcc(row: AccountRow): Account =
    return Account(
        id: row.id,
        username: row.username,
        passwordHash: row.passwordHash,
        isEphemeral: row.isEphemeral,
        creationDate: row.creationDate
    )

proc initAccounts*() {.async.} =
    ## Initializes the accounts system using the settings and implementation in the provided Config object.
    ## The initDb proc should have already been called by this point.

    # Delete all ephemeral accounts
    await db.deleteEphemeralAccounts()

proc verifyPassword*(account: Account, password: string): Future[bool] {.inline.} =
    ## Verifies whether a password matches the password hash of the provided Account object
    
    return verifyPassword(password, account.passwordHash)

proc createAccount*(username: string, password: string, metadata: Option[Metadata], isEphemeral: bool): Future[Account] {.async.} =
    ## Creates a new account (check if the username is taken first)

    let hash = await hashPassword(password)
    let res = await insertAccount(username, hash, metadata, isEphemeral)
    
    return accRowToAcc(res)

proc deleteAccountById*(id: AccountId) {.async.} =
    ## Deletes the account with the specified ID
    
    await db.deleteAccountById(id)

proc deleteAccountByUsername*(username: string) {.async.} =
    ## Deletes the account with the specified username
    
    await db.deleteAccountByUsername(username)

proc fetchAccountById*(id: AccountId): Future[Option[Account]] {.async.} =
    ## Fetches the account with the specified ID

    let res = await db.fetchAccountById(id)

    if res.isSome:
        return some(accRowToAcc(res.get))
    else:
        return none[Account]()

proc fetchAccountByUsername*(username: string): Future[Option[Account]] {.async.} =
    ## Fetches the account with the specified username

    let res = await db.fetchAccountByUsername(username)

    if res.isSome:
        return some(accRowToAcc(res.get))
    else:
        return none[Account]()

proc registerConnect*(client: ref Client) =
    ## Registers a client connection
    
    # TODO Add to accounts in use

proc registerDisconnect*(client: ref Client) =
    ## Registers an account disconnection
    
    # TODO Remove from accounts in use
    # If there are no more accounts with this username connected AND it's marked as ephemeral, delete it