Class BronzeWars.Data.NationMigration Extends %RegisteredObject
{
/// Convert old faction identities without resetting armies or unit strengths.
ClassMethod Run() As %Status
{
    set oldFaction = "ASSYRIAN", newFaction = "HITTITE"
    tstart
    try {
        &sql(DECLARE LegacyProfileCursor CURSOR FOR
             SELECT %ID, UnitType FROM BronzeWars_Model.UnitProfile WHERE Faction = :oldFaction)
        &sql(OPEN LegacyProfileCursor)
        do ..CheckSQL(SQLCODE, $get(%msg))
        for {
            &sql(FETCH LegacyProfileCursor INTO :profileId, :unitTypeId)
            quit:(SQLCODE=100)
            do ..CheckSQL(SQLCODE, $get(%msg))
            set legacyProfiles(profileId) = unitTypeId
        }
        &sql(CLOSE LegacyProfileCursor)
        set profileId = ""
        for {
            set profileId = $order(legacyProfiles(profileId)) quit:profileId=""
            set unitTypeId = legacyProfiles(profileId)
            set target = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(unitTypeId, newFaction)
            if $isobject(target) {
                set targetId = target.%Id()
                &sql(UPDATE BronzeWars_Model.BattleUnit SET UnitProfile = :targetId WHERE UnitProfile = :profileId)
                do ..CheckSQL(SQLCODE, $get(%msg))
                &sql(DELETE FROM BronzeWars_Model.UnitProfile WHERE %ID = :profileId)
            } else {
                &sql(UPDATE BronzeWars_Model.UnitProfile SET Faction = :newFaction WHERE %ID = :profileId)
            }
            do ..CheckSQL(SQLCODE, $get(%msg))
        }
        &sql(UPDATE BronzeWars_Model.Army SET Faction = :newFaction WHERE Faction = :oldFaction)
        do ..CheckSQL(SQLCODE, $get(%msg))
        tcommit
    } catch exception {
        trollback 1
        return exception.AsStatus()
    }
    return $$$OK
}

ClassMethod CheckSQL(code As %Integer, message As %String) [ Private ]
{
    if code < 0 throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Nation migration failed: " _ code _ " " _ message))
}
}
