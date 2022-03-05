import std/[json, jsonutils, strutils, os, nativesockets, options]
import objects, exceptions

proc createConfigFromJson*(json: JsonNode): Config =
    ## Creates a Config object from the provided JSON

    # Deserialize JSON into base config
    var baseConf = json.jsonTo(BaseConfig)

    # Determine database type
    var dbConf: DatabaseConfig
    var kindOrd: int
    let typeStr = baseConf.databaseType.toLowerAscii()
    case typeStr:
    of "memory":
        kindOrd = DatabaseConfigKind.Memory.ord
    of "sqlite":
        kindOrd = DatabaseConfigKind.Sqlite.ord
    of "postgres":
        kindOrd = DatabaseConfigKind.Postgres.ord
    of "mysql":
        kindOrd = DatabaseConfigKind.MySql.ord
    else:
        raise newConfigError("Unknown database type specified in config: "&typeStr)

    # Serialize accordingly
    baseConf.database{"kind"} = newJInt(kindOrd)
    dbConf = baseConf.database.jsonTo(DatabaseConfig)

    # Create full config objcet
    return Config(
        host: baseConf.host,
        port: baseConf.port,
        password: baseConf.password,
        allowCreateAccounts: baseConf.allowCreateAccounts,
        allowPublishStreams: baseConf.allowPublishStreams,
        authTimeoutSeconds: baseConf.authTimeoutSeconds,
        maxClients: baseConf.maxClients,
        maxStreams: baseConf.maxStreams,
        maxClientsPerHost: baseConf.maxClientsPerHost,
        enableManagement: baseConf.enableManagement,
        streamKeepAliveSeconds: baseConf.streamKeepAliveSeconds,
        managerPassword: baseConf.managerPassword,
        managerWhitelist: baseConf.managerWhitelist,
        databaseType: baseConf.databaseType,
        database: baseConf.database,
        databaseConfig: dbConf
    )

proc createConfigFromFile*(path: string): Config =
    ## Creates a Config object from the contents of the provided file

    return createConfigFromJson(parseFile(path))

proc createJsonFromConfig*(config: Config): JsonNode =
    ## Creates JSON object from a Config object
    
    # Create a base config object
    var baseConf = BaseConfig(
        host: config.host,
        port: config.port,
        password: config.password,
        allowCreateAccounts: config.allowCreateAccounts,
        allowPublishStreams: config.allowPublishStreams,
        authTimeoutSeconds: config.authTimeoutSeconds,
        maxClients: config.maxClients,
        maxStreams: config.maxStreams,
        maxClientsPerHost: config.maxClientsPerHost,
        enableManagement: config.enableManagement,
        streamKeepAliveSeconds: config.streamKeepAliveSeconds,
        managerPassword: config.managerPassword,
        managerWhitelist: config.managerWhitelist,
        databaseType: config.databaseType
    )

    # Populate database field
    baseConf.database = config.databaseConfig.toJson()
    baseConf.database.delete("kind")

    # Serialize and return
    return baseConf.toJson()

proc createDefaultConfig*(): Config =
    ## Creates and returns a default Config object
    
    return Config(
        host: "0.0.0.0",
        port: Port(1350),
        password: none[string](),
        allowCreateAccounts: true,
        allowPublishStreams: true,
        authTimeoutSeconds: 30,
        maxClients: 1000,
        maxStreams: 100,
        maxClientsPerHost: 5,
        enableManagement: true,
        streamKeepAliveSeconds: 120,
        managerPassword: none[string](),
        managerWhitelist: none[seq[string]](),
        databaseType: "sqlite",
        database: newJObject(),
        databaseConfig: DatabaseConfig(
            kind: DatabaseConfigKind.Sqlite,
            sqliteDbPath: "server.db"
        )
    )

proc createDefaultConfigJson*(): JsonNode =
    ## Creates and returns a default JSON config object
    
    return createJsonFromConfig(createDefaultConfig())

proc writeDefaultConfig*(path: string) =
    ## Writes the default config to a file at the specified path
    
    writeFile(path, createDefaultConfigJson().pretty())