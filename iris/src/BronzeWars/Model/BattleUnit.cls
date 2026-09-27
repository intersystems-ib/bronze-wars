Class BronzeWars.Model.BattleUnit Extends (%Persistent, %JSON.Adaptor)
{
Relationship Battle As BronzeWars.Model.Battle [ Cardinality = one, Inverse = Units, Required ];
Relationship Army As BronzeWars.Model.Army [ Cardinality = one, Inverse = Units, Required ];
Relationship UnitType As BronzeWars.Model.UnitType [ Cardinality = one, Inverse = BattleUnits, Required ];
Relationship UnitProfile As BronzeWars.Model.UnitProfile [ Cardinality = one, Inverse = BattleUnits ];
Property Name As %String(MAXLEN = 100);
Property CurrentStrength As %Integer(MINVAL = 0) [ Required ];
Property CurrentProjectiles As %Integer(MINVAL = 0) [ InitialExpression = 0, Required ];
Property Morale As %Integer(MAXVAL = 100, MINVAL = 0) [ InitialExpression = 100, Required ];
Property MovementSpent As %Integer(MINVAL = 0) [ InitialExpression = 0, Required ];
Property PositionX As %Integer(MINVAL = 0);
Property PositionY As %Integer(MINVAL = 0);
Property IsDeployed As %Boolean [ InitialExpression = 0, Required ];
Property HasMoved As %Boolean [ InitialExpression = 0, Required ];
Property HasAttacked As %Boolean [ InitialExpression = 0, Required ];
Property Active As %Boolean [ InitialExpression = 1, Required ];
Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)}, Required ];

Index BattleIndex On Battle;
Index ArmyIndex On Army;
Index UnitTypeIndex On UnitType;

Method %OnNew(unitType As BronzeWars.Model.UnitType = "", unitProfile As BronzeWars.Model.UnitProfile = "") As %Status [ Private, ServerOnly = 1 ]
{
    if $isobject(unitType) {
        set ..UnitType = unitType
        set ..CurrentStrength = unitType.InitialStrength
        set ..CurrentProjectiles = unitType.InitialProjectiles
    }
    if $isobject(unitProfile) {
        set ..UnitProfile = unitProfile
        set ..CurrentStrength = unitProfile.InitialStrength
    }
    return $$$OK
}

Method %OnValidateObject() As %Status [ Private, ServerOnly = 1 ]
{
    if ..IsDeployed, ((..PositionX = "") ! (..PositionY = "")) {
        return $$$ERROR($$$GeneralError, "A deployed unit requires both coordinates")
    }
    if $isobject(..Army), $isobject(..Battle), (..Army.Battle.%Id() '= ..Battle.%Id()) {
        return $$$ERROR($$$GeneralError, "Army and unit must belong to the same battle")
    }
    return $$$OK
}
}
