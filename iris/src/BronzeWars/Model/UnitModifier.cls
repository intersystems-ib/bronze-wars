Class BronzeWars.Model.UnitModifier Extends (%Persistent, %JSON.Adaptor)
{
Relationship AttackerType As BronzeWars.Model.UnitType [ Cardinality = one, Inverse = OutgoingModifiers, Required ];
Relationship DefenderType As BronzeWars.Model.UnitType [ Cardinality = one, Inverse = IncomingModifiers, Required ];
Property AttackModifier As %Integer [ Required ];
Property Description As %String(MAXLEN = 250);
Property Active As %Boolean [ InitialExpression = 1, Required ];

Index MatchupIndex On (AttackerType, DefenderType) [ Unique ];

ClassMethod GetAttackModifier(attackerType As BronzeWars.Model.UnitType, defenderType As BronzeWars.Model.UnitType) As %Integer
{
    set sc = $$$OK
    set modifier = ..MatchupIndexOpen(attackerType.%Id(), defenderType.%Id(), .sc)
    if $SYSTEM.Status.IsError(sc) return 0
    if '$isobject(modifier) return 0
    if 'modifier.Active return 0
    return modifier.AttackModifier
}
}
