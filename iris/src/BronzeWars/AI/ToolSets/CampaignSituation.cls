Class BronzeWars.AI.ToolSets.CampaignSituation Extends %AI.ToolSet
{
XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="BronzeWarsCampaignSituation">
  <Description>Situacion estrategica y opciones de movimiento legales bajo la niebla de guerra.</Description>
  <Policies><Audit Class="BronzeWars.AI.Policies.ToolAudit"/></Policies>
  <Tool Name="GetCampaignSituation" Class="BronzeWars.AI.Tools.CampaignSituation" Method="GetCampaignSituation">
    <Description>Devuelve ejercitos propios, invasores detectados y opciones de defensa, recuperacion, saqueo y conquista para el turno actual. No revela ejercitos ocultos.</Description>
  </Tool>
</ToolSet>
}
}
