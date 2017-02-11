//================================================================
// ExtVoting.EVMut
// ----------------
// ...
// ----------------
// by Chatouille
//================================================================
class EVMut extends CRZMutator;

function InitMutator(String Options, out String ErrorMessage)
{
	CRZGame(WorldInfo.Game).VoteManagerClassName = "ExtVoting.EVManager";

	Super.InitMutator(Options, ErrorMessage);
}

defaultproperties
{
}
