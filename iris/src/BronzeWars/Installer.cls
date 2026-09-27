Class BronzeWars.Installer Extends %RegisteredObject
{

ClassMethod ConfigureWebApplication() As %Status
{
    set applicationNamespace = $namespace
    set application = "/api/bronzewars"
    kill properties
    set properties("NameSpace") = "BRONZEWARS"
    set properties("DispatchClass") = "BronzeWars.Rest.API"
    set properties("Enabled") = 1
    set properties("AutheEnabled") = 64
    set properties("MatchRoles") = ":%All"
    set properties("CookiePath") = application _ "/"
    set properties("Recurse") = 1

    zn "%SYS"
    if ##class(Security.Applications).Exists(application) {
        set sc = ##class(Security.Applications).Modify(application, .properties)
    } else {
        set sc = ##class(Security.Applications).Create(application, .properties)
    }
    zn applicationNamespace

    return sc
}

ClassMethod ConfigureProduction() As %Status
{
    set production = "BronzeWars.Interop.Production"
    set ^Ens.Configuration("csp", "LastProduction") = production
    set sc = ##class(Ens.Director).SetAutoStart(production)
    return:$SYSTEM.Status.IsError(sc) sc

    if ##class(Ens.Director).IsProductionRunning(.runningProduction) {
        if runningProduction '= production return $$$ERROR($$$GeneralError, "Another production is already running: " _ runningProduction)

        // Business hosts are long-lived processes. A full restart guarantees that
        // they execute the routines just compiled by the installer.
        set sc = ##class(Ens.Director).StopProduction()
        return:$SYSTEM.Status.IsError(sc) sc
    }
    return ##class(Ens.Director).StartProduction(production)
}

}
