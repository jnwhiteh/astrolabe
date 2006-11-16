--[[
Name: Astrolabe
Revision: $Rev$
$Date$
Author(s): Esamynn (jcarrothers@gmail.com)
Inspired By: Gatherer by Norganna
             MapLibrary by Kristofer Karlsson (krka@kth.se)
Website: http://esamynn.wowinterface.com/
Documentation: 
SVN: 
Description:
	This is a library for the World of Warcraft UI system to place
	icons accurately on both the Minimap and the Worldmaps accurately
	and maintain the accuracy of those positions.  

License:

Copyright (C) 2006  James Carrothers

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
]]

local LIBRARY_VERSION_MAJOR = "Astrolabe"
local LIBRARY_VERSION_MINOR = "$Revision$"

local _G = getfenv(0)
local previous = _G[LIBRARY_VERSION_MAJOR]
if previous and not previous:IsNewVersion(LIBRARY_VERSION_MAJOR, LIBRARY_VERSION_MINOR) then return end

local Astrolabe = {};

-- define local variables for Data Tables (defined at the end of this file)
local WorldMapSize, MinimapSize;

--------------------------------------------------------------------------------------------------------------
-- Working Tables
--------------------------------------------------------------------------------------------------------------

Astrolabe.LastPlayerPosition = {};
Astrolabe.MinimapIcons = {};
Astrolabe.WorldMapIcons = {};


--------------------------------------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------------------------------------

function Astrolabe:PlaceIconOnMinimap( minimap, icon, continent, zone, xPos, yPos )
	-- check argument types
	self:argCheck(minimap, 2, "table");
	self:assert(minimap.GetZoom and minimap.GetWidth and minimap.GetHeight, "Usage Message");
	self:argCheck(icon, 3, "table");
	self:assert(icon.SetPoint and icon.ClearAllPoints, "Usage Message");
	self:argCheck(continent, 4, "number");
	self:argCheck(zone, 5, "number", "nil");
	self:argCheck(xPos, 6, "number");
	self:argCheck(yPos, 7, "number");
	
	local lC, lZ, lx, ly = unpack(self.LastPlayerPosition);
	local dist, xDist, yDist = self:ComputeDistance(lC, lZ, lx, ly, continent, zone, xPos, yPos);
	if not ( dist ) then
		--icon's position has no meaningful position relative to the player's current location
		return false;
	end
	local iconData = self.MinimapIcons[icon];
	if not ( iconData ) then
		iconData = {
			continent = continent,
			zone = zone,
			xPos = xPos,
			yPos = yPos,
			dist = dist,
			xDist = xDist,
			yDist = yDist,
		};
		self.MinimapIcons[icon] = iconData;
	
	else
		iconData.continent = continent;
		iconData.zone = zone;
		iconData.xPos = xPos;
		iconData.yPos = yPos;
		iconData.dist = dist;
		iconData.xDist = xDist;
		iconData.yDist = yDist;
	
	end
	
	return true;
end

function Astrolabe:RemoveIconFromMinimap( minimap, icon )
	if not ( self.MinimapIcons[icon] ) then
		return false;
	end
	self.MinimapIcons[icon] = nil;
	icon:Hide();
	return true;
end

function Astrolabe:PlaceIconOnWorldMap( worldMapFrame, icon, continent, zone, xPos, yPos )
	-- check argument types
	self:argCheck(worldMapFrame, 2, "table");
	self:assert(worldMapFrame.GetWidth and worldMapFrame.GetHeight, "Usage Message");
	self:argCheck(icon, 3, "table");
	self:assert(icon.SetPoint and icon.ClearAllPoints, "Usage Message");
	self:argCheck(continent, 4, "number");
	self:argCheck(zone, 5, "number", "nil");
	self:argCheck(xPos, 6, "number");
	self:argCheck(yPos, 7, "number");
	
	
end

function Astrolabe:RemoveIconFromWorldMap( worldMapFrame, icon )
	
	
end

local function getContPosition( zoneData, z, x, y )
	if ( z and z ~= 0 ) then
		zoneData = zoneData[z];
		x = x * zoneData.width + zoneData.xOffset;
		y = y * zoneData.height + zoneData.yOffset;
	else
		x = x * zoneData.width;
		y = y * zoneData.height;
	end
	return x, y;
end

function Astrolabe:ComputeDistance( c1, z1, x1, y1, c2, z2, x2, y2 )
	local dist, xDelta, yDelta;
	if ( c1 == c2 and z1 == z2 ) then
		-- points in the same zone
		local zoneData = WorldMapSize[c1];
		if ( z1 and z1 ~= 0 ) then
			zoneData = zoneData[z1];
		end
		xDelta = (x2 - x1) * zoneData.width;
		yDelta = (y2 - y1) * zoneData.height;
	
	elseif ( c1 == c1 ) then
		-- points on the same continent
		local zoneData = WorldMapSize[c1];
		x1, y1 = getContPosition(zoneData, z1, x1, y1);
		x2, y2 = getContPosition(zoneData, z2, x2, y2);
		xDelta = (x2 - x1);
		yDelta = (y2 - y1);
	
	else
		local cont1 = WorldMapSize[c1];
		local cont2 = WorldMapSize[c2];
		if ( cont1.parentContinent == cont2.parentContinent ) then
			if ( c1 ~= cont1.parentContinent ) then
				x1, y1 = getContPosition(cont1, z1, x1, y1);
				x1 = x1 + cont1.xOffset;
				y1 = y1 + cont1.yOffset;
			end
			if ( c2 ~= cont2.parentContinent ) then
				x2, y2 = getContPosition(cont2, z2, x2, y2);
				x2 = x2 + cont2.xOffset;
				y2 = y2 + cont2.yOffset;
			end
			
			xDelta = (x2 - x1) * zoneData.width;
			yDelta = (y2 - y1) * zoneData.height;
		end
	
	end
	if ( xDelta and yDelta ) then
		dist = sqrt(xDelta*xDelta + yDelta*yDelta);
	end
	return dist, xDelta, yDelta;
end

function Astrolabe:SetMapToCurrentZone()
	if ( self.onCurrentWorldMap ) then
		return;
	end
	SetMapToCurrentZone();
end

function Astrolabe:GetCurrentPlayerPosition()
	self:SetMapToCurrentZone();
	local C, Z = GetCurrentMapContinent(), GetCurrentMapZone();
	local x, y = GetPlayerMapPosition("player");
	if ( x <= 0 and y <= 0 ) then
		SetMapZoom(C);
		Z = 0;
		x, y = GetPlayerMapPosition("player");
		if ( x <= 0 and y <= 0 ) then
			-- we are in an instance or otherwise off the continent map
			return;
		end
	end
	return C, Z, x, y;
end


--------------------------------------------------------------------------------------------------------------
-- Minimap Icon Placement Updates
--------------------------------------------------------------------------------------------------------------

local function placeIconOnMinimap( minimap, minimapZoom, mapWidth, mapHeight, icon, dist, xDist, yDist )
	--TODO: add support for non-circular minimaps
	local mapDiameter;
	if ( Astrolabe.minimapOutside ) then
		mapDiameter = MinimapSize.outdoor[minimapZoom];
	else
		mapDiameter = MinimapSize.indoor[minimapZoom];
	end
	local mapRadius = mapDiameter / 2;
	local xScale = mapDiameter / mapWidth;
	local yScale = mapDiameter / mapHeight;
	local iconDiameter = icon:GetWidth() * xScale;
	
	icon:ClearAllPoints();
	if ( (dist + iconDiameter) > mapRadius ) then
		-- position along the outside of the Minimap
		local factor = (mapRadius - iconDiameter) / dist;
		xDist = xDist * factor;
		yDist = yDist * factor;
	end
	icon:SetPoint("CENTER", minimap, "CENTER", xDist/xScale, -yDist/yScale);
end

local lastZoom;

function Astrolabe:UpdateMinimapIconPositions()
	local C, Z, x, y = self:GetCurrentPlayerPosition();
	if not ( C and Z and x and y ) then
		self.processingFrame:Hide();
	end
	local Minimap = Minimap;
	local lastPosition = self.LastPlayerPosition;
	local lC, lZ, lx, ly = unpack(lastPosition);
	--[[
	if not ( lC and lZ and lx and ly ) then
		self:CalculateMinimapIconPositions();
		return;
	end
	--]]
	if ( lC == C and lZ == Z and lx == x and ly == y ) then
		-- player has not moved since the last update
		if ( lastZoom ~= Minimap:GetZoom() ) then
			local currentZoom = Minimap:GetZoom();
			lastZoom = currentZoom;
			local mapWidth = Minimap:GetWidth();
			local mapHeight = Minimap:GetHeight();
			for icon, data in pairs(self.MinimapIcons) do
				placeIconOnMinimap(Minimap, currentZoom, mapWidth, mapHeight, icon, data.dist, data.xDist, data.yDist);
			end
		end
		return;
	end
	local _, xDelta, yDelta = self:ComputeDistance(lC, lZ, lx, ly, C, Z, x, y);
	local currentZoom = Minimap:GetZoom();
	lastZoom = currentZoom;
	local mapWidth = Minimap:GetWidth();
	local mapHeight = Minimap:GetHeight();
	for icon, data in pairs(self.MinimapIcons) do
		local xDist = data.xDist - xDelta;
		local yDist = data.yDist - yDelta;
		local dist = sqrt(xDist*xDist + yDist*yDist);
		placeIconOnMinimap(Minimap, currentZoom, mapWidth, mapHeight, icon, dist, xDist, yDist);
		
		data.dist = dist;
		data.xDist = xDist;
		data.yDist = yDist;
	end
	
	lastPosition[1] = C;
	lastPosition[2] = Z;
	lastPosition[3] = x;
	lastPosition[4] = y;
end

function Astrolabe:CalculateMinimapIconPositions()
	local C, Z, x, y = self:GetCurrentPlayerPosition();
	if not ( C and Z and x and y ) then
		self.processingFrame:Hide();
	end
	
	local currentZoom = Minimap:GetZoom();
	lastZoom = currentZoom;
	local Minimap = Minimap;
	local mapWidth = Minimap:GetWidth();
	local mapHeight = Minimap:GetHeight();
	for icon, data in pairs(self.MinimapIcons) do
		local dist, xDist, yDist = self:ComputeDistance(C, Z, x, y, data.continent, data.zone, data.xPos, data.yPos);
		placeIconOnMinimap(Minimap, currentZoom, mapWidth, mapHeight, icon, dist, xDist, yDist);
		
		data.dist = dist;
		data.xDist = xDist;
		data.yDist = yDist;
	end
	
	local lastPosition = self.LastPlayerPosition;
	lastPosition[1] = C;
	lastPosition[2] = Z;
	lastPosition[3] = x;
	lastPosition[4] = y;
end


--------------------------------------------------------------------------------------------------------------
-- World Map Icon Placement Updates
--------------------------------------------------------------------------------------------------------------




--------------------------------------------------------------------------------------------------------------
-- Handler Scripts
--------------------------------------------------------------------------------------------------------------

function Astrolabe:OnEvent( frame, event )
	if ( event == "MINIMAP_UPDATE_ZOOM" ) then
		-- update minimap zoom scale
		local Minimap = Minimap;
		local curZoom = Minimap:GetZoom();
		if ( GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") ) then
			if ( curZoom < 2 ) then
				Minimap:SetZoom(curZoom + 1);
			else
				Minimap:SetZoom(curZoom - 1);
			end
		end
		if ( GetCVar("minimapZoom")+0 == Minimap:GetZoom() ) then
			self.minimapOutside = true;
		else
			self.minimapOutside = false;
		end
		Minimap:SetZoom(curZoom);
		
		self:CalculateMinimapIconPositions();
	
	elseif ( event == "WORLD_MAP_UPDATE" ) then
		self.onCurrentWorldMap = false;
	
	elseif ( event == "PLAYER_LEAVING_WORLD" ) then
		frame:Hide();
		--dump all minimap icons
		--TODO
	
	elseif ( event == "PLAYER_ENTERING_WORLD" ) then
		frame:Show();
	
	elseif ( event == "ZONE_CHANGED_NEW_AREA" ) then
		self.onCurrentWorldMap = false;
		frame:Show();
	
	end
end

local updateTimer = 0;

function Astrolabe:OnUpdate( frame, elapsed )
	updateTimer = updateTimer + elapsed;
	if ( updateTimer < 0.2 ) then
		return;
	end
	updateTimer = 0;
	self:UpdateMinimapIconPositions();
end

function Astrolabe:OnShow( frame )
	self:CalculateMinimapIconPositions();
end


--------------------------------------------------------------------------------------------------------------
-- Library Registration
--------------------------------------------------------------------------------------------------------------

local function activate( self, oldLib, oldDeactivate )
	Astrolabe = self;
	local frame = self.processingFrame;
	if not ( frame ) then
		frame = CreateFrame("Frame");
		self.processingFrame = frame;
	end
	frame:SetParent("Minimap");
	frame:Hide();
	frame:UnregisterAllEvents();
	frame:RegisterEvent("MINIMAP_UPDATE_ZOOM");
	frame:RegisterEvent("WORLD_MAP_UPDATE");
	frame:RegisterEvent("PLAYER_LEAVING_WORLD");
	frame:RegisterEvent("PLAYER_ENTERING_WORLD");
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
	frame:SetScript("OnEvent",
		function( frame, event, ... )
			self:OnEvent(frame, event, ...);
		end
	);
	frame:SetScript("OnUpdate",
		function( frame, elapsed )
			self:OnUpdate(frame, elapsed);
		end
	);
	frame:SetScript("OnShow",
		function( frame )
			self:OnShow(frame);
		end
	);
	frame:Show();
	
	if not ( self.ContinentList ) then
		self.ContinentList = { GetMapContinents() };
		for C in pairs(self.ContinentList) do
			local zones = { GetMapZones(C) };
			self.ContinentList[C] = zones;
			for Z in ipairs(zones) do
				SetMapZoom(C, Z);
				zones[Z] = GetMapInfo();
			end
		end
	end
	
	_G[LIBRARY_VERSION_MAJOR] = self
end

AceLibrary:Register(Astrolabe, LIBRARY_VERSION_MAJOR, LIBRARY_VERSION_MINOR, activate)


--------------------------------------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------------------------------------

-- diameter of the Minimap in game yards at
-- the various possible zoom levels
MinimapSize = {
	indoor = {
		[0] = 300, -- scale
		[1] = 240, -- 1.25
		[2] = 180, -- 5/3
		[3] = 120, -- 2.5
		[4] = 80,  -- 3.75
		[5] = 50,  -- 6
	},
	outdoor = {
		[0] = 466 + 2/3, -- scale
		[1] = 400,       -- 7/6
		[2] = 333 + 1/3, -- 1.4
		[3] = 266 + 2/6, -- 1.75
		[4] = 200,       -- 7/3
		[5] = 133 + 1/3, -- 3.5
	},
}

-- distances across and offsets of the world maps
-- in game yards
WorldMapSize = {
	-- World Map of Azeroth
	[0] = {
		parentContinent = 0,
		height = 29687.90575403711,
		width = 44531.82907938571,
	},
	-- Kalimdor
	[1] = {
		height = 24532.39670836129,
		width = 36798.56388065484,
		height = 24532.39670836129,
		yOffset = 1815.149000954498,
		xOffset = -8310.762035321373,
		zoneData = {
			AzuremystIsle = {
				xOffset = 9966.264785353642,
				height = 2714.490705490833,
				yOffset = 5460.139378090237,
				width = 4070.69191624402,
			},
			Moonglade = {
				xOffset = 18447.22621439156,
				height = 1539.533678644292,
				yOffset = 4308.091789071822,
				width = 2308.254834810441,
			},
			Barrens = {
				xOffset = 14443.19903105646,
				height = 6756.02766886921,
				yOffset = 11187.03430854273,
				width = 10132.98263386783,
			},
			ThousandNeedles = {
				xOffset = 17499.32929341832,
				height = 2933.241274801781,
				yOffset = 16766.0151133423,
				width = 4399.86408093722,
			},
			Ashenvale = {
				xOffset = 15366.08027406009,
				height = 3843.6274509507,
				yOffset = 8126.716152815559,
				width = 5766.471113365882,
			},
			Teldrassil = {
				xOffset = 13251.58449896318,
				height = 3393.632169760774,
				yOffset = 968.6223632831094,
				width = 5091.467863261983,
			},
			Mulgore = {
				xOffset = 15018.17646021543,
				height = 3424.887145969537,
				yOffset = 13072.3896812124,
				width = 5137.320937418651,
			},
			Felwood = {
				xOffset = 15424.4116748014,
				height = 3833.206376333299,
				yOffset = 5666.381311442203,
				width = 5749.804647660601,
			},
			Darkshore = {
				xOffset = 14124.4534386827,
				height = 4366.525717349431,
				yOffset = 4466.419105960455,
				width = 6549.780280774227,
			},
			Aszhara = {
				xOffset = 20342.99141400156,
				height = 3381.138765234094,
				yOffset = 7457.989394368407,
				width = 5070.67050845317,
			},
			Desolace = {
				xOffset = 12832.80723200791,
				height = 2997.808472061639,
				yOffset = 12347.420176847,
				width = 4495.726850591816,
			},
			Winterspring = {
				xOffset = 17382.67868933953,
				height = 4733.19093874495,
				yOffset = 4266.421320915687,
				width = 7099.756078049356,
			},
			Tanaris = {
				xOffset = 17284.7655865671,
				height = 4599.847335452487,
				yOffset = 18674.28905369955,
				width = 6899.765399158027,
			},
			ThunderBluff = {
				xOffset = 16549.3979631063,
				height = 695.8106558315811,
				yOffset = 13649.45350182988,
				width = 1043.656960810915,
			},
			TheExodar = {
				xOffset = 10532.61275516805,
				height = 704.6641703983867,
				yOffset = 6276.045028807911,
				width = 1056.732317707214,
			},
			Durotar = {
				xOffset = 19028.49705185168,
				height = 3524.884411530582,
				yOffset = 10991.20668781479,
				width = 5287.216492267496,
			},
			UngoroCrater = {
				xOffset = 16532.70803775362,
				height = 2466.588521980951,
				yOffset = 18765.95157787033,
				width = 3699.872808671185,
			},
			Silithus = {
				xOffset = 14528.60591761034,
				height = 2322.839629859208,
				yOffset = 18757.61998086822,
				width = 3483.224287356748,
			},
			BloodmystIsle = {
				xOffset = 9541.280691875327,
				height = 2174.923922716305,
				yOffset = 3424.790637352243,
				width = 3262.385067990556,
			},
			Dustwallow = {
				xOffset = 18040.98792657193,
				height = 3499.925994238187,
				yOffset = 14832.74627547471,
				width = 5249.825246684532,
			},
			StonetalonMountains = {
				xOffset = 13820.29750397374,
				height = 3256.14191702356,
				yOffset = 9882.909063258192,
				width = 4883.173287670144,
			},
			Darnassis = {
				xOffset = 14127.75729935019,
				height = 705.7102838625475,
				yOffset = 2561.497770365212,
				width = 1058.300884213672,
			},
			Feralas = {
				xOffset = 11624.54217828119,
				height = 4633.182754891688,
				yOffset = 15166.06954533647,
				width = 6949.760203962193,
			},
		},
	},
	-- Eastern Kingdoms
	[2] = {
		parentContinent = 0,
		width = 44531.82907938571,
		height = 29687.90575403711,
		yOffset = 672.394243898962,
		xOffset = 15525.46116176085,
		zoneData = {
			SearingGorge = {
				xOffset = 20549.79216718034,
				height = 1759.323814324105,
				yOffset = 18089.1130859905,
				width = 2638.983497441373,
			},
			BurningSteppes = {
				xOffset = 20483.260695433,
				height = 2308.80653395524,
				yOffset = 19190.53829660411,
				width = 3464.439206371018,
			},
			Hilsbrad = {
				xOffset = 18906.27124745732,
				height = 2523.175382751244,
				yOffset = 10401.30820862141,
				width = 3784.768623002945,
			},
			Duskwood = {
				xOffset = 19182.24863185023,
				height = 2128.932318659681,
				yOffset = 22366.68575249847,
				width = 3193.397126147125,
			},
			Hinterlands = {
				xOffset = 22030.67644729586,
				height = 3035.697244183049,
				yOffset = 9139.718113185238,
				width = 4553.547761833218,
			},
			BlastedLands = {
				xOffset = 21636.42381484464,
				height = 2641.452937228378,
				yOffset = 23372.01545158768,
				width = 3962.192644867957,
			},
			Ironforge = {
				xOffset = 21011.85832482857,
				height = 624.0259499358332,
				yOffset = 16278.61963254376,
				width = 935.1005541546348,
			},
			WesternPlaguelands = {
				xOffset = 19675.07169842483,
				height = 3390.51604889238,
				yOffset = 6892.516193591386,
				width = 5085.748111973363,
			},
			Elwynn = {
				xOffset = 18351.86380115633,
				height = 2737.547484763449,
				yOffset = 20264.86137790052,
				width = 4105.096781649925,
			},
			Arathi = {
				xOffset = 21192.90413872658,
				height = 2838.560609102086,
				yOffset = 11032.11372300997,
				width = 4257.866868433815,
			},
			Alterac = {
				xOffset = 19241.40097238752,
				height = 2207.781855191136,
				yOffset = 9100.292100754092,
				width = 3311.650981011242,
			},
			Wetlands = {
				xOffset = 20628.63998090106,
				height = 3259.905388826016,
				yOffset = 13414.82945162126,
				width = 4891.122323232433,
			},
			EasternPlaguelands = {
				xOffset = 22752.64228436313,
				height = 3052.959590892036,
				yOffset = 6379.982883924112,
				width = 4578.183340860992,
			},
			Westfall = {
				xOffset = 16599.93733936097,
				height = 2759.720980154896,
				yOffset = 21992.15486787662,
				width = 4139.58581163175,
			},
			LochModan = {
				xOffset = 22525.95067644204,
				height = 2175.747618551866,
				yOffset = 16181.94422787321,
				width = 3262.388005359779,
			},
			DeadwindPass = {
				xOffset = 21153.48011301306,
				height = 1971.235617424019,
				yOffset = 22544.0956266096,
				width = 2956.847801992818,
			},
			SwampOfSorrows = {
				xOffset = 22796.99678548859,
				height = 1808.61207678567,
				yOffset = 22253.33469175312,
				width = 2712.903970076898,
			},
			Redridge = {
				xOffset = 22025.74405435591,
				height = 1712.506269407682,
				yOffset = 21016.39323584379,
				width = 2567.545089469422,
			},
			Stranglethorn = {
				xOffset = 17541.1995670008,
				height = 5031.556951894251,
				yOffset = 24084.12273454082,
				width = 7547.351771587034,
			},
			DunMorogh = {
				xOffset = 18036.4700055975,
				height = 3883.343815563809,
				yOffset = 15459.97657602722,
				width = 5824.98852296331,
			},
		},
	},
	-- Outland
	[3] = {
		parentContinent = 3,
		width = 17463.5328406368,
		height = 11642.3552270912,
		zoneData = {
			Netherstorm = {
				xOffset = 7512.471490955926,
				height = 3716.54982251816,
				yOffset = 365.0985587119766,
				width = 5574.825692372223,
			},
			Hellfire = {
				xOffset = 7456.223213706637,
				height = 3443.642767820014,
				yOffset = 4339.973600978067,
				width = 5164.421775975702,
			},
			BladesEdgeMountains = {
				xOffset = 4150.066771630121,
				height = 3616.553810935776,
				yOffset = 1412.981869580586,
				width = 5424.85486469095,
			},
			ShattrathCity = {
				xOffset = 6860.566181245488,
				height = 870.806186802335,
				yOffset = 7295.086222613707,
				width = 1306.208144809405,
			},
			Zangarmarsh = {
				xOffset = 3520.933392353017,
				height = 3351.977572594424,
				yOffset = 3885.82186032646,
				width = 5026.919940829795,
			},
			ShadowmoonValley = {
				xOffset = 8770.765422136874,
				height = 3666.547917042889,
				yOffset = 7769.034259125071,
				width = 5499.827432644565,
			},
			TerokkarForest = {
				xOffset = 5912.52148134923,
				height = 3599.891642719214,
				yOffset = 6821.146015884529,
				width = 5399.830631678504,
			},
			Nagrand = {
				xOffset = 2700.122240774119,
				height = 3683.220868119114,
				yOffset = 5779.511201243053,
				width = 5524.826567895654,
			},
		},
	},
}

for continent, zones in pairs(Astrolabe.ContinentList) do
	local mapData = WorldMapSize[continent];
	for index, mapName in pairs(zones) do
		if not ( mapData.zoneData[mapName] ) then
			---WE HAVE A PROBLEM!!!
		end
		mapData[index] = mapData.zoneData[mapName];
		mapData.zoneData[mapName] = nil;
	end
end
