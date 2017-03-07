//================================================================
// ExtVoting.EVReplicationInfo
// ----------------
// - fixing the client crash when too many voting options
// - optimized vote option transfer with 
//    * one transfer for a distinct list of all game names
//    * one transfer per map with map name + vote indices for each game (0 = not available, 1=vote index 0, ...)
// ----------------
// by Chatouille and PredatH0r
//================================================================

class EVReplicationInfo extends CRZVoteReplicationInfo;

struct MapVoteInfo
{
  var string MapName;
  var int VoteIndex[16];
};

var bool bSortGameVoteList;
var bool bFillVotingList;
var CRZVoteListInterface FillVotingList_List;
var array<MapVoteInfo> mapInfos;
var string options[16];
var int optionCount, mapCount, mapIndex;

// keep a hard reference to the MapPreviews.upk package to force-download them to clients
var Texture Rankin;


simulated event PostBeginPlay()
{
	Super.PostBeginPlay();

	if ( WorldInfo.NetMode != NM_DedicatedServer )
		SetTimer(1.0, true, 'UpdateVoteList');	// better performance with a 1sec timer than Tick
}

function EnableTransfers()
{		
	//start slowly transfering the other games (using 0.1sec per map instead of 0.2sec per entry)
	SetTimer(0.1 * WorldInfo.TimeDilation, True, 'TransferTimer');
}

function TransferTimer()
{
  local int i, m, o;
  local string MapAndGame, map, game;
  local byte NumVotes;

  if (VoteManager == none)
    return;

  if (mapCount == 0 && optionCount == 0)
  {
    for (i=0; i<VoteManager.VoteGames.Length; i++)
    {
  	  if (!VoteManager.GetMapAndGameStringByVoteIndex(i, MapAndGame, NumVotes))
        continue;
		
      class'CRZVoteManager'.static.SplitMapAndName(MapAndGame,Map,Game);

      // find/add option(=game) index
      for (o=0; o<optionCount; o++)
      {
        if (options[o] == game)
          break;
      }
      if (o == optionCount)
      {
        options[o] = game;
        ++optionCount;
      }

      // find/add map index
      for (m=0; m<mapCount; m++)
      {
        if (mapInfos[m].MapName == map)
          break;
      }
      if (m == mapCount)
      {
        mapInfos.Add(1);
        mapInfos[m].MapName = map;
        ++mapCount;
      }
    
      // set the vote index (use +1 so that a value of 0 means that the combination of map/game is not used)
      mapInfos[m].VoteIndex[o] = i + 1;
    }
  
    ClientReceiveOptions(options);

    if(VoteManager.GetMapAndGameOfCurrentMapCycle(MapAndGame))
			ClientReceiveNextCycleMap(MapAndGame);
    return;
  }

  if (mapIndex < mapCount)
    ClientReceiveMapVoteData(mapInfos[mapIndex++]);
  else
  {
    ClearTimer('TransferTimer');
    ClientBeginVoting();
  }
}

simulated reliable client function ClientReceiveOptions(string _options[16])
{
  local int i;
  for (i = 0; i < ArrayCount(_options); i++)
  {
    options[i] = _options[i];
    if (options[i] != "")
      optionCount = i+1;
  }
}

simulated reliable client function ClientReceiveMapVoteData(MapVoteInfo mapInfo)
{
  local byte NumVotes;
  local int i;

  NumVotes = 0;
  for (i=0; i<optionCount; i++)
  {
    if (mapInfo.VoteIndex[i] != 0)
      ClientReceiveMapVoteInfo(mapInfo.VoteIndex[i] - 1, mapInfo.MapName $ "," $ options[i], NumVotes);
  }
}

// Defer the sorting to next Tick
simulated function SortGameVoteList()
{
	bSortGameVoteList = true;
}

// Defer the interface update to next Tick
simulated function FillVotingList(CRZVoteListInterface UIVoteList)
{
	bFillVotingList = true;
	FillVotingList_List = UIVoteList;
}

simulated function UpdateVoteList()
{
	if ( bSortGameVoteList )
	{
		Super.SortGameVoteList();
		bSortGameVoteList = false;
	}
	if ( bFillVotingList )
	{
		//Super.FillVotingList(FillVotingList_List);
		Modified_FillVotingList(FillVotingList_List);
		bFillVotingList = false;
	}
}

// copy from CRZVoteReplicationInfo, but using our own code for GetPreviewImage()
simulated function Modified_FillVotingList( CRZVoteListInterface UIVoteList)
{
  local int i;
  local string LastMap, mapname;
  local CRZUIDataProvider_MapInfo CurrentMapDataProvider;
  local GFxClikWidget GFxContainer;
  local WorldInfo WI;
  local CRZLocalPlayer LP;
  local bool bFullGame;

  //ATTENTION in this case we are recreating the complete list everytime, since we can't modify/refilling with different elements them like in the lobbyview

  if(UIVoteList == none)
    return;

  //if we have the full game EVERY map is available
  LP = CRZLocalPlayer(class'UIInteraction'.static.GetLocalPlayer(0));
  if(LP != none)
    bFullGame = LP.isFullGame();

  //clear
  UIVoteList.ClearList(0);

  //replaymap is highest voted OR if nobody voted yet AND if we dont have a nextCycleGame --> show the infos of the current map
  if(BestVotedGameIdx==0 || (BestVotedGameIdx==255 && NextCycleGame.VoteGameIdx!=1) )
  {
    WI = class'WorldInfo'.static.GetWorldInfo();
    CurrentMapDataProvider = CRZMapInfo(WI.GetMapInfo()).GetMapDataProvider();
    mapname = CurrentMapDataProvider!= none ? CurrentMapDataProvider.GetMapFriendlyName() : WI.GetMapName(false);

    if(CRZHudMovie(UIVoteList) == none)
    {	
      UIVoteList.AddPicture(GetPreviewImage(CurrentMapDataProvider, mapname), class'CRZUIDataProvider_MapInfo'.static.isMapAvailable(CurrentMapDataProvider,bFullGame), 100,0);
      UIVoteList.AddItem("Label", "maplable",, 1).SetString("text",mapname);//fill with currentmapname if no dataprovider (no sure if the Dataprovider can be none, maybe on downloaded map)

      UIVoteList.AddItem("Label", "modelabel", class'CRZHudMovie'.default.UIGrey04HexColor, 0).SetString("text",class'GFxCRZUIScoreboardBase'.default.ModeLabel$":"@class<UTGame>(WI.GetGameClass()).default.GameName);
      UIVoteList.AddItem("Label", "voteslabel", class'CRZHudMovie'.default.UIGrey04HexColor, 0).SetString("text",class'CRZHudMovie'.default.VotingReplay$":"@class'CRZHud'.static.FormatInteger(GameVotesClientList[0].NumVotes,2));//allways display element 0
      UIVoteList.AddItem("Border", "Border1",class'CRZHudMovie'.default.UIGrey01HexColor , 0);
    }
    else
      CRZHudMovie(UIVoteList).SetCurrentMapInfo(false, class'GFxCRZUIScoreboardBase'.default.MapLabel$": "$(mapname)$"\n"$class'GFxCRZUIScoreboardBase'.default.ModeLabel$":"@class<UTGame>(WI.GetGameClass()).default.GameName$"\n"$class'CRZHudMovie'.default.VotingReplay$":"@class'CRZHud'.static.FormatInteger(GameVotesClientList[0].NumVotes,2) ,GetPreviewImage(CurrentMapDataProvider, mapname), class'CRZUIDataProvider_MapInfo'.static.isMapAvailable(CurrentMapDataProvider,bFullGame));
  }
  else if(BestVotedGameIdx==255 && NextCycleGame.VoteGameIdx==1)//if voted for nothing AND we have a next cycle game, display the nextcyclegame
  {
    if(CRZHudMovie(UIVoteList) == none)
    {	
      UIVoteList.AddPicture(GetPreviewImage(NextCycleGame.MapInfo, NextCycleGame.MapName), class'CRZUIDataProvider_MapInfo'.static.isMapAvailable(NextCycleGame.MapInfo,bFullGame) ,100,0);
      UIVoteList.AddItem("Label", "maplable",, 1).SetString("text",NextCycleGame.MapName);
      UIVoteList.AddItem("Label", "modelabel", class'CRZHudMovie'.default.UIGrey04HexColor, 0).SetString("text",class'GFxCRZUIScoreboardBase'.default.ModeLabel$":"@NextCycleGame.GameMode);
      //UIVoteList.AddItem("Label", "voteslabel", class'CRZHudMovie'.default.UIGrey04HexColor, 0).SetString("text",class'CRZHudMovie'.default.VotesLabel$":"@class'CRZHud'.static.FormatInteger(GameVotesClientList[BestVotedGameIdx].NumVotes,2));
      UIVoteList.AddItem("Border", "Border1",class'CRZHudMovie'.default.UIGrey01HexColor , 0);
    }
    else
      CRZHudMovie(UIVoteList).SetCurrentMapInfo(false, class'GFxCRZUIScoreboardBase'.default.MapLabel$": "$NextCycleGame.MapName$"\n"$class'GFxCRZUIScoreboardBase'.default.ModeLabel$":"@NextCycleGame.GameMode/*$"\n"$class'CRZHudMovie'.default.VotesLabel$":"@class'CRZHud'.static.FormatInteger(GameVotesClientList[BestVotedGameIdx].NumVotes,2)*/   , GetPreviewImage(NextCycleGame.MapInfo, NextCycleGame.MapName), class'CRZUIDataProvider_MapInfo'.static.isMapAvailable(NextCycleGame.MapInfo,bFullGame));
  }
  else //voted for a map in the votelist
  {
    if(CRZHudMovie(UIVoteList) == none)
    {	
      UIVoteList.AddPicture(GetPreviewImage(GameVotesClientList[BestVotedGameIdx].MapInfo, SortedGameVotesList[i].MapName),  class'CRZUIDataProvider_MapInfo'.static.isMapAvailable(GameVotesClientList[BestVotedGameIdx].MapInfo,bFullGame),100,0);
      UIVoteList.AddItem("Label", "maplable",, 1).SetString("text",GameVotesClientList[BestVotedGameIdx].MapName);
      UIVoteList.AddItem("Label", "modelabel", class'CRZHudMovie'.default.UIGrey04HexColor, 0).SetString("text",class'GFxCRZUIScoreboardBase'.default.ModeLabel$":"@GameVotesClientList[BestVotedGameIdx].GameMode);
      UIVoteList.AddItem("Label", "voteslabel", class'CRZHudMovie'.default.UIGrey04HexColor, 0).SetString("text",class'CRZHudMovie'.default.VotesLabel$":"@class'CRZHud'.static.FormatInteger(GameVotesClientList[BestVotedGameIdx].NumVotes,2));
      UIVoteList.AddItem("Border", "Border1",class'CRZHudMovie'.default.UIGrey01HexColor , 0);
    }
    else
      CRZHudMovie(UIVoteList).SetCurrentMapInfo(false, class'GFxCRZUIScoreboardBase'.default.MapLabel$": "$GameVotesClientList[BestVotedGameIdx].MapName$"\n"$class'GFxCRZUIScoreboardBase'.default.ModeLabel$":"@GameVotesClientList[BestVotedGameIdx].GameMode$"\n"$class'CRZHudMovie'.default.VotesLabel$":"@class'CRZHud'.static.FormatInteger(GameVotesClientList[BestVotedGameIdx].NumVotes,2)   , GetPreviewImage(GameVotesClientList[BestVotedGameIdx].MapInfo, GameVotesClientList[BestVotedGameIdx].MapName),class'CRZUIDataProvider_MapInfo'.static.isMapAvailable(GameVotesClientList[BestVotedGameIdx].MapInfo,bFullGame));
  }
     
  //this list needs to be presorted
  for(i=0; i<SortedGameVotesList.Length; i++)
  {
    //if NOT almost the same.....NOTE the very first element (the replay element) will also fail since the mapname is empty, check "else branch"
    if(!(SortedGameVotesList[i].MapName~=LastMap))
    {
      UIVoteList.AddPicture(GetPreviewImage(SortedGameVotesList[i].MapInfo, SortedGameVotesList[i].MapName), class'CRZUIDataProvider_MapInfo'.static.isMapAvailable(SortedGameVotesList[i].MapInfo,bFullGame), 100,8);//this fills the defaultimage if no Mapinfo
      UIVoteList.AddItem("Label", "mapname"$i , , 8).SetString("text",SortedGameVotesList[i].MapName);
      
      //first gamemode of this map     using the name as gameIdx so we can use it for the click listener
      GFxContainer = GFxClikWidget(UIVoteList.AddItem("RadioButton", string(SortedGameVotesList[i].VoteGameIdx) ,"0x000001" , 0));
      GFxContainer.SetString("labelID",SortedGameVotesList[i].GameMode@"-"@class'CRZHud'.static.FormatInteger(SortedGameVotesList[i].NumVotes,2));
    
      GFxContainer.AddEventListener('CLIK_click', OnLevelSelectionChanged);
    }
    else
    {
      //all following gamemodes of this map
      GFxContainer = GFxClikWidget(UIVoteList.AddItem("RadioButton", string(SortedGameVotesList[i].VoteGameIdx) ,"0x000001" , 0));
      //if element 0 use the Replay string
      GFxContainer.SetString("labelID",(SortedGameVotesList[i].VoteGameIdx==0 ? class'CRZHudMovie'.default.VotingReplay : SortedGameVotesList[i].GameMode) @"-"@class'CRZHud'.static.FormatInteger(SortedGameVotesList[i].NumVotes,2));
      GFxContainer.AddEventListener('CLIK_click', OnLevelSelectionChanged);
    }	

    if(SortedGameVotesList[i].VoteGameIdx == CurVoteGameIndex)
      GFxContainer.SetBool("selected", true);

    LastMap=SortedGameVotesList[i].MapName;


    //if last element OR the next element is gonna be diffrent -> draw border
    if(i+1>=SortedGameVotesList.Length || !(SortedGameVotesList[i].MapName~=SortedGameVotesList[i+1].MapName))
      UIVoteList.AddItem("Border", "Border2",class'CRZHudMovie'.default.UIGrey01HexColor , 1);
  }
}


/**
 * returns the previewimage of a MapDataProvider.
 * if no provider specified or no imagepath ->returns defaultimage
 * */
simulated function string GetPreviewImage(CRZUIDataProvider_MapInfo MapData, string MapName)
{
  local Texture PreviewImage;

  if(MapData != none && MapData.PreviewImageMarkup!="")
  {
    PreviewImage = Texture(DynamicLoadObject(MapData.PreviewImageMarkup,class'Texture',true));//this way we can check if its a valid path...not sure if this is cool
    if(PreviewImage != none)
      return "img://" $ MapData.PreviewImageMarkup;
  }
  
  if (MapName == "" && MapData != none)
    MapName = MapData.MapName;
  if (MapName != "")
  {
    PreviewImage = Texture(DynamicLoadObject("MapPreviews.LevelPrevs." $ Repl(MapName, " ", "_"), class'Texture', true));
    if(PreviewImage != none)
    {
      //`log("returning map picture for " $ MapName);
      return "img://MapPreviews.LevelPrevs." $ MapName;
    }
  }

  //if everything failed, return the default image
  //`log("returning default map picture for " $ MapName);
  return "img://" $ class'GFxCRZFrontEndPlayer_Base'.default.DefaultMapPreviewPicture;
}

defaultproperties
{
	Rankin=Texture2D'MapPreviews.LevelPrevs.Rankin_V1'
}
