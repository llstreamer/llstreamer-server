import std/[locks, tables, asyncdispatch, options]
import db/[]
import objects, idgen, client, crypto

type
    AccountsInUse = tuple[
        lock: Lock,
        accounts: Table[string, Account]
    ]

var conf: Config

proc initAccounts*(config: Config) =
    ## Initializes the accounts system using the settings and implementation in the provided Config object
    
    conf = config

    # TODO Initialize the database based on the backend
    # Backends: memory, sqlite, postgresql, mysql

proc verifyPassword(account: Account, password: string): Future[bool] {.inline.} =
    ## Verifies whether a password matches the password hash of the provided Account object
    
    return verifyPassword(password, account.passwordHash)

proc createAccount(username: string, password: string) {.async.} =
    ## Creates a new account (check if the username is taken first)

    let hash = await hashPassword(password)
    echo ""

proc fetchAccountById(id: AccountId): Future[Option[Account]] {.async.} =
    ## Fetches the account with the specified ID

    var res = none[Account]()

proc fetchAccountByUsername(username: string): Future[Option[Account]] {.async.} =
    ## Fetches the account with the specified username

    echo ""

proc registerConnect(username: string, client: Client) =
    echo ""
proc registerDisconnect(username: string, client: Client) =
    echo ""