import std/[db_common, db_sqlite, db_postgres, db_mysql, strformat, sequtils, strutils, sugar]

import ".."/[logging, exceptions]

type
    Migration* = object
        ## A database migration

        id*: uint ## The migration ID
        name*: string ## The migration name
        sqlite*: seq[string] ## Migration queries for SQLite
        postgres*: seq[string] ## Migration queries for PostgreSQL
        mysql*: seq[string] ## Migration queries for MySQL
    
    SupportedDbConn* = db_sqlite.DbConn | db_postgres.DbConn | db_mysql.DbConn
        ## Supported database connections

const databaseMigrations* = [
    Migration(
        id: 1,
        name: "Initial schema",
        sqlite: @[
            """
            CREATE TABLE accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_username VARCHAR(24) NOT NULL,
                account_password_hash TEXT NOT NULL,
                account_metadata VARCHAR(65535),
                account_ephemeral BOOLEAN NOT NULL,
                account_creation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
            )
            """,
            """
            CREATE TABLE streams (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                stream_owner INTEGER NOT NULL,
                stream_name VARCHAR(24) NOT NULL,
                stream_published BOOLEAN NOT NULL,
                stream_key VARCHAR(24) NOT NULL,
                stream_custodian_key VARCHAR(24) NOT NULL,
                stream_metadata VARCHAR(65535),
                stream_creation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
            )
            """,
            """
            UPDATE SQLITE_SEQUENCE SET seq = 1 WHERE name = 'accounts'
            """,
            """
            UPDATE SQLITE_SEQUENCE SET seq = 1 WHERE name = 'streams'
            """
        ]
    )
]

proc applyMigrations*[T: SupportedDbConn](conn: T) =
    ## Applies migrations on an SQLite database
    
    # Create migrations table if it doesn't already exist
    var createTableSql: SqlQuery
    if conn is db_sqlite.DbConn:
        createTableSql = sql"""
        CREATE TABLE IF NOT EXISTS migrations (
            id INTEGER PRIMARY KEY,
            migration_name TEXT NOT NULL,
            migration_creation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
        )
        """
    elif conn is db_postgres.DbConn:
        raise newDatabaseMigrationError("PostgreSQL support has not yet been implemented")
    elif conn is db_mysql.DbConn:
        raise newDatabaseMigrationError("MySQL support has not yet been implemented")
    conn.exec(createTableSql)

    # Fetch which migrations have already been applied
    let appliedMigrations = conn
        .getAllRows(sql"SELECT id FROM migrations")
        .map((row: seq[string]) => parseUInt(row[0]))
    
    # If this is not the first time, then it is an upgrade and messages will be printed
    let isUpgrade = appliedMigrations.len > 0
    
    # Apply all unapplied migrations
    for migration in databaseMigrations:
        if migration.id notin appliedMigrations:
            if isUpgrade:
                logInfo fmt"Upgrading database to v{migration.id}: {migration.name}"
            
            # Apply migration SQL and create entry in migrations table
            var stmts: seq[string]
            if conn is db_sqlite.DbConn:
                stmts = migration.sqlite
            elif conn is db_postgres.DbConn:
                stmts = migration.postgres
            elif conn is db_mysql.DbConn:
                stmts = migration.mysql
            for stmt in stmts:
                conn.exec(sql(stmt))
            conn.exec(sql"INSERT INTO migrations (id, migration_name) VALUES (?, ?)", migration.id, migration.name)