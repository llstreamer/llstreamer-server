import std/terminal

proc logInfo*(msg: string) =
    ## Logs an info message

    stdout.styledWriteLine(styleBright, fgGreen, "[I]", resetStyle, " "&msg)

proc logError*(msg: string) =
    ## Logs an error message

    stderr.styledWriteLine(styleBright, fgRed, "[E]", resetStyle, fgRed, " "&msg, resetStyle)

proc logWarn*(msg: string) =
    ## Logs a warning message
    
    stderr.styledWriteLine(styleBright, fgYellow, "[W]", resetStyle, fgYellow, " "&msg, resetStyle)

proc logError*(msg: string, exception: ref Exception, exceptionMsg: string) =
    ## Logs an error message with an exception
    
    logError(msg)
    logError("\tException: "&repr(exception))
    logError("\tMessage: "&exceptionMsg)