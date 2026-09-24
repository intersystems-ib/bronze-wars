Class BronzeWars.Interop.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="BronzeWars.Interop.Production" TestingEnabled="true" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Unit Type Service" ClassName="BronzeWars.Service.UnitTypeService" PoolSize="0" Enabled="true" Foreground="false" InactivityTimeout="0" />
  <Item Name="Battle Service" ClassName="BronzeWars.Service.BattleService" PoolSize="0" Enabled="true" Foreground="false" InactivityTimeout="0" />
  <Item Name="Deployment Service" ClassName="BronzeWars.Service.DeploymentService" PoolSize="0" Enabled="true" Foreground="false" InactivityTimeout="0" />
  <Item Name="Unit Type Process" ClassName="BronzeWars.Process.UnitTypeProcess" PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" />
  <Item Name="Battle Process" ClassName="BronzeWars.Process.BattleProcess" PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" />
  <Item Name="Deployment Process" ClassName="BronzeWars.Process.DeploymentProcess" PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" />
  <Item Name="Data Operation" ClassName="BronzeWars.Operation.DataOperation" PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" />
  <Item Name="LLM Operation" ClassName="BronzeWars.Operation.LLMOperation" PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="120" />
</Production>
}

}
