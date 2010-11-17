--[[
Name: Astrolabe
Revision: $Rev$
$Date$
Author(s): Esamynn (esamynn at wowinterface.com)
Inspired By: Gatherer by Norganna
             MapLibrary by Kristofer Karlsson (krka at kth.se)
Documentation: http://wiki.esamynn.org/Astrolabe
SVN: http://svn.esamynn.org/astrolabe/
Description:
	This is a library for the World of Warcraft UI system to place
	icons accurately on both the Minimap and on Worldmaps.  
	This library also manages and updates the position of Minimap icons 
	automatically.  

Copyright (C) 2006-2010 James Carrothers

License:
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

Note:
	This library's source code is specifically designed to work with
	World of Warcraft's interpreted AddOn system.  You have an implicit
	licence to use this library with these facilities since that is its
	designated purpose as per:
	http://www.fsf.org/licensing/licenses/gpl-faq.html#InterpreterIncompat
]]

-- WARNING!!!
-- DO NOT MAKE CHANGES TO THIS LIBRARY WITHOUT FIRST CHANGING THE LIBRARY_VERSION_MAJOR
-- STRING (to something unique) OR ELSE YOU MAY BREAK OTHER ADDONS THAT USE THIS LIBRARY!!!
local LIBRARY_VERSION_MAJOR = "Astrolabe-1.0"
local LIBRARY_VERSION_MINOR = tonumber(string.match("$Revision$", "(%d+)") or 1)

if not DongleStub then error(LIBRARY_VERSION_MAJOR .. " requires DongleStub.") end
if not DongleStub:IsNewerVersion(LIBRARY_VERSION_MAJOR, LIBRARY_VERSION_MINOR) then return end

local Astrolabe = {};

-- define local variables for Data Tables (defined at the end of this file)
local WorldMapSize, MinimapSize, ValidMinimapShapes, zeroData;

function Astrolabe:GetVersion()
	return LIBRARY_VERSION_MAJOR, LIBRARY_VERSION_MINOR;
end


--------------------------------------------------------------------------------------------------------------
-- Config Constants
--------------------------------------------------------------------------------------------------------------

local configConstants = { 
	MinimapUpdateMultiplier = true, 
}

-- this constant is multiplied by the current framerate to determine
-- how many icons are updated each frame
Astrolabe.MinimapUpdateMultiplier = 1;


--------------------------------------------------------------------------------------------------------------
-- Working Tables
--------------------------------------------------------------------------------------------------------------

Astrolabe.LastPlayerPosition = { 0, 0, 0, 0 };
Astrolabe.MinimapIcons = {};
Astrolabe.IconsOnEdge = {};
Astrolabe.IconsOnEdge_GroupChangeCallbacks = {};

Astrolabe.MinimapIconCount = 0
Astrolabe.ForceNextUpdate = false;
Astrolabe.IconsOnEdgeChanged = false;

-- This variable indicates whether we know of a visible World Map or not.  
-- The state of this variable is controlled by the AstrolabeMapMonitor library.  
Astrolabe.WorldMapVisible = false;

local AddedOrUpdatedIcons = {}
local MinimapIconsMetatable = { __index = AddedOrUpdatedIcons }


--------------------------------------------------------------------------------------------------------------
-- Local Pointers for often used API functions
--------------------------------------------------------------------------------------------------------------

local twoPi = math.pi * 2;
local atan2 = math.atan2;
local sin = math.sin;
local cos = math.cos;
local abs = math.abs;
local sqrt = math.sqrt;
local min = math.min
local max = math.max
local yield = coroutine.yield
local next = next
local GetFramerate = GetFramerate

local real_GetCurrentMapAreaID = GetCurrentMapAreaID
local function GetCurrentMapAreaID()
	local id = real_GetCurrentMapAreaID();
	if ( id < 0 and GetCurrentMapContinent() == WORLDMAP_WORLD_ID ) then
		return 0;
	end
	return id;
end


--------------------------------------------------------------------------------------------------------------
-- Internal Utility Functions
--------------------------------------------------------------------------------------------------------------

local function assert(level,condition,message)
	if not condition then
		error(message,level)
	end
end

local function argcheck(value, num, ...)
	assert(1, type(num) == "number", "Bad argument #2 to 'argcheck' (number expected, got " .. type(level) .. ")")
	
	for i=1,select("#", ...) do
		if type(value) == select(i, ...) then return end
	end
	
	local types = strjoin(", ", ...)
	local name = string.match(debugstack(2,2,0), ": in function [`<](.-)['>]")
	error(string.format("Bad argument #%d to 'Astrolabe.%s' (%s expected, got %s)", num, name, types, type(value)), 3)
end

local function getContPosition( mapData, f, x, y )
	if ( f ~= 0 ) then
		mapData = mapData[f];
	end
	x = x * mapData.width + mapData.xOffset;
	y = y * mapData.height + mapData.yOffset;
	return x, y;
end


--------------------------------------------------------------------------------------------------------------
-- General Utility Functions
--------------------------------------------------------------------------------------------------------------

function Astrolabe:ComputeDistance( m1, f1, x1, y1, m2, f2, x2, y2 )
	--[[
	argcheck(m1, 2, "number");
	assert(3, c1 >= 0, "ComputeDistance: Illegal map id to m1: "..m1);
	argcheck(f1, 3, "number", "nil");
	argcheck(x1, 4, "number");
	argcheck(y1, 5, "number");
	argcheck(m2, 6, "number");
	assert(3, c2 >= 0, "ComputeDistance: Illegal map id to m2: "..m2);
	argcheck(f2, 7, "number", "nil");
	argcheck(x2, 8, "number");
	argcheck(y2, 9, "number");
	--]]
	
	f1 = f1 or 0;
	f2 = f2 or 0;
	
	local dist, xDelta, yDelta;
	if ( m1 == m2 and f1 == f2 ) then
		-- points in the same zone on the same floor
		local mapData = WorldMapSize[m1];
		if ( f1 ~= 0 ) then
			mapData = mapData[f1];
		end
		xDelta = (x2 - x1) * mapData.width;
		yDelta = (y2 - y1) * mapData.height;
	
	else
		local map1 = WorldMapSize[m1];
		local map2 = WorldMapSize[m2];
		if ( map1 == zeroData or map2 == zeroData ) then
			-- do nothing
		
		elseif ( map1.system == map2.system ) then
			-- points on the same continent
			x1, y1 = getContPosition(map1, f1, x1, y1);
			x2, y2 = getContPosition(map2, f2, x2, y2);
			xDelta = (x2 - x1);
			yDelta = (y2 - y1);
		
		else
			local c1 = map1.system;
			local c2 = map2.system;
			local cont1 = WorldMapSize[c1];
			local cont2 = WorldMapSize[c2];
			if ( cont1.parent == cont2.parent ) then
				local worldID = cont1.parent;
				x1, y1 = getContPosition(map1, f1, x1, y1);
				x2, y2 = getContPosition(map2, f2, x2, y2);
				if not ( c1 == cont1.parent ) then
					cont1 = WorldMapSize[worldID][c1];
					x1 = x1 - cont1.xOffset;
					y1 = y1 - cont1.yOffset;
				end
				if not ( c2 == cont2.parent ) then
					cont2 = WorldMapSize[worldID][c2];
					x2 = x2 - cont2.xOffset;
					y2 = y2 - cont2.yOffset;
				end
				
				xDelta = x2 - x1;
				yDelta = y2 - y1;
			end
		
		end
	
	end
	if ( xDelta and yDelta ) then
		dist = sqrt(xDelta*xDelta + yDelta*yDelta);
	end
	return dist, xDelta, yDelta;
end

function Astrolabe:TranslateWorldMapPosition( M, F, xPos, yPos, nM, nF )
	--[[
	argcheck(M, 2, "number");
	argcheck(F, 3, "number", "nil");
	argcheck(xPos, 4, "number");
	argcheck(yPos, 5, "number");
	argcheck(nM, 6, "number");
	argcheck(nF, 7, "number", "nil");
	--]]
	
	F = F or 0;
	nF = nF or 0;
	if ( nM < 0 ) then
		return;
	end
	
	local mapData;
	if ( M == nM and F == nF ) then
		return xPos, yPos;
	
	else
		local map = WorldMapSize[M];
		local nMap = WorldMapSize[nM];
		if ( map == zeroData or nMap == zeroData ) then
			return;
		
		elseif ( M == nM or (map.system == nMap.system) ) then
			-- points on the same continent
			mapData = WorldMapSize[M];
			xPos, yPos = getContPosition(mapData, F, xPos, yPos);
			mapData = WorldMapSize[nM];
			if ( nF ~= 0 ) then
				mapData = mapData[nF];
			end
			xPos = xPos - mapData.xOffset;
			yPos = yPos - mapData.yOffset;
		
		else
			-- different continents, same world
			local C = map.system;
			local nC = nMap.system;
			local cont = WorldMapSize[C];
			local nCont = WorldMapSize[nC];
			if ( cont.parent == nCont.parent ) then
				local worldID = nCont.parent;
				mapData = WorldMapSize[M];
				xPos, yPos = getContPosition(mapData, F, xPos, yPos);
				if ( M ~= worldID ) then
					-- translate up to world map if we aren't there already
					cont = WorldMapSize[worldID][C];
					xPos = xPos - cont.xOffset;
					yPos = yPos - cont.yOffset;
					mapData = WorldMapSize[worldID];
				end
				if ( nM ~= worldID ) then
					-- translate down to the new continent
					nCont = WorldMapSize[worldID][nC];
					xPos = xPos + nCont.xOffset;
					yPos = yPos + nCont.yOffset;
					mapData = WorldMapSize[nM];
					if ( nF ~= 0 ) then
						mapData = mapData[nF];
					end
				end
			
			else
				return;
			end
		
		end
	
	end
	
	return (xPos / mapData.width), (yPos / mapData.height);
end

--*****************************************************************************
-- This function will do its utmost to retrieve some sort of valid position 
-- for the specified unit, including changing the current map zoom (if needed).  
-- Map Zoom is returned to its previous setting before this function returns.  
--*****************************************************************************
function Astrolabe:GetUnitPosition( unit, noMapChange )
	local x, y = GetPlayerMapPosition(unit);
	if ( x <= 0 and y <= 0 ) then
		if ( noMapChange ) then
			-- no valid position on the current map, and we aren't allowed
			-- to change map zoom, so return
			return;
		end
		local lastMapID, lastFloor = GetCurrentMapAreaID(), GetCurrentMapDungeonLevel();
		SetMapToCurrentZone();
		x, y = GetPlayerMapPosition(unit);
		if ( x <= 0 and y <= 0 ) then
			WorldMapZoomOutButton_OnClick();
			x, y = GetPlayerMapPosition(unit);
			if ( x <= 0 and y <= 0 ) then
				-- we are in an instance or otherwise off map
				return;
			end
		end
		local M, F = GetCurrentMapAreaID(), GetCurrentMapDungeonLevel();
		if ( M ~= lastMapID or F ~= lastFloor ) then
			-- set map zoom back to what it was before
			SetMapByID(lastMapID);
			SetDungeonMapLevel(lastFloor);
		end
		return M, F, x, y;
	end
	return GetCurrentMapAreaID(), GetCurrentMapDungeonLevel(), x, y;
end

--*****************************************************************************
-- This function will do its utmost to retrieve some sort of valid position 
-- for the specified unit, including changing the current map zoom (if needed).  
-- However, if a monitored WorldMapFrame (See AstrolabeMapMonitor.lua) is 
-- visible, then will simply return nil if the current zoom does not provide 
-- a valid position for the player unit.  Map Zoom is returned to its previous 
-- setting before this function returns, if it was changed.  
--*****************************************************************************
function Astrolabe:GetCurrentPlayerPosition()
	return self:GetUnitPosition("player", self.WorldMapVisible);
end

function Astrolabe:GetMapID(continent, zone)
	zone = zone or 0;
	local ret = self.ContinentList[continent];
	if ( ret ) then
		return ret[zone];
	end
	if ( continent == 0 and zone == 0 ) then
		return 0;
	end
end


--------------------------------------------------------------------------------------------------------------
-- Working Table Cache System
--------------------------------------------------------------------------------------------------------------

local tableCache = {};
tableCache["__mode"] = "v";
setmetatable(tableCache, tableCache);

local function GetWorkingTable( icon )
	if ( tableCache[icon] ) then
		return tableCache[icon];
	else
		local T = {};
		tableCache[icon] = T;
		return T;
	end
end


--------------------------------------------------------------------------------------------------------------
-- Minimap Icon Placement
--------------------------------------------------------------------------------------------------------------

--*****************************************************************************
-- local variables specifically for use in this section
--*****************************************************************************
local minimapRotationEnabled = false;
local minimapShape = false;

local minimapRotationOffset = GetPlayerFacing();


local function placeIconOnMinimap( minimap, minimapZoom, mapWidth, mapHeight, icon, dist, xDist, yDist )
	local mapDiameter;
	if ( Astrolabe.minimapOutside ) then
		mapDiameter = MinimapSize.outdoor[minimapZoom];
	else
		mapDiameter = MinimapSize.indoor[minimapZoom];
	end
	local mapRadius = mapDiameter / 2;
	local xScale = mapDiameter / mapWidth;
	local yScale = mapDiameter / mapHeight;
	local iconDiameter = ((icon:GetWidth() / 2) + 3) * xScale;
	local iconOnEdge = nil;
	local isRound = true;
	
	if ( minimapRotationEnabled ) then
		local sinTheta = sin(minimapRotationOffset)
		local cosTheta = cos(minimapRotationOffset)
		--[[
		Math Note
		The math that is acutally going on in the next 3 lines is:
			local dx, dy = xDist, -yDist
			xDist = (dx * cosTheta) + (dy * sinTheta)
			yDist = -((-dx * sinTheta) + (dy * cosTheta))
		
		This is because the origin for map coordinates is the top left corner
		of the map, not the bottom left, and so we have to reverse the vertical 
		distance when doing the our rotation, and then reverse the result vertical 
		distance because this rotation formula gives us a result with the origin based 
		in the bottom left corner (of the (+, +) quadrant).  
		The actual code is a simplification of the above.  
		]]
		local dx, dy = xDist, yDist
		xDist = (dx * cosTheta) - (dy * sinTheta)
		yDist = (dx * sinTheta) + (dy * cosTheta)
	end
	
	if ( minimapShape and not (xDist == 0 or yDist == 0) ) then
		isRound = (xDist < 0) and 1 or 3;
		if ( yDist < 0 ) then
			isRound = minimapShape[isRound];
		else
			isRound = minimapShape[isRound + 1];
		end
	end
	
	-- for non-circular portions of the Minimap edge
	if not ( isRound ) then
		dist = max(abs(xDist), abs(yDist))
	end

	if ( (dist + iconDiameter) > mapRadius ) then
		-- position along the outside of the Minimap
		iconOnEdge = true;
		local factor = (mapRadius - iconDiameter) / dist;
		xDist = xDist * factor;
		yDist = yDist * factor;
	end
	
	if ( Astrolabe.IconsOnEdge[icon] ~= iconOnEdge ) then
		Astrolabe.IconsOnEdge[icon] = iconOnEdge;
		Astrolabe.IconsOnEdgeChanged = true;
	end
	
	icon:ClearAllPoints();
	icon:SetPoint("CENTER", minimap, "CENTER", xDist/xScale, -yDist/yScale);
end

function Astrolabe:PlaceIconOnMinimap( icon, mapID, mapFloor, xPos, yPos )
	-- check argument types
	argcheck(icon, 2, "table");
	assert(3, icon.SetPoint and icon.ClearAllPoints, "Usage Message");
	argcheck(mapID, 3, "number");
	argcheck(mapFloor, 4, "number", "nil");
	argcheck(xPos, 5, "number");
	argcheck(yPos, 6, "number");
	
	-- if the positining system is currently active, just use the player position used by the last incremental (or full) update
	-- otherwise, make sure we base our calculations off of the most recent player position (if one is available)
	local lM, lF, lx, ly;
	if ( self.processingFrame:IsShown() ) then
		lM, lF, lx, ly = unpack(self.LastPlayerPosition);
	else
		lM, lF, lx, ly = self:GetCurrentPlayerPosition();
		if ( lM and lM >= 0 ) then
			local lastPosition = self.LastPlayerPosition;
			lastPosition[1] = lM;
			lastPosition[2] = lF;
			lastPosition[3] = lx;
			lastPosition[4] = ly;
		else
			lM, lF, lx, ly = unpack(self.LastPlayerPosition);
		end
	end
	
	local dist, xDist, yDist = self:ComputeDistance(lM, lF, lx, ly, mapID, mapFloor, xPos, yPos);
	if not ( dist ) then
		--icon's position has no meaningful position relative to the player's current location
		return -1;
	end
	
	local iconData = GetWorkingTable(icon);
	if ( self.MinimapIcons[icon] ) then
		self.MinimapIcons[icon] = nil;
	else
		self.MinimapIconCount = self.MinimapIconCount + 1
	end
	
	AddedOrUpdatedIcons[icon] = iconData
	iconData.mapID = mapID;
	iconData.mapFloor = mapFloor;
	iconData.xPos = xPos;
	iconData.yPos = yPos;
	iconData.dist = dist;
	iconData.xDist = xDist;
	iconData.yDist = yDist;
	
	minimapRotationEnabled = GetCVar("rotateMinimap") ~= "0"
	if ( minimapRotationEnabled ) then
		minimapRotationOffset = GetPlayerFacing();
	end
	
	-- check Minimap Shape
	minimapShape = GetMinimapShape and ValidMinimapShapes[GetMinimapShape()];
	
	-- place the icon on the Minimap and :Show() it
	local map = Minimap
	placeIconOnMinimap(map, map:GetZoom(), map:GetWidth(), map:GetHeight(), icon, dist, xDist, yDist);
	icon:Show()
	
	-- We know this icon's position is valid, so we need to make sure the icon placement system is active.  
	self.processingFrame:Show()
	
	return 0;
end

function Astrolabe:RemoveIconFromMinimap( icon )
	if not ( self.MinimapIcons[icon] ) then
		return 1;
	end
	AddedOrUpdatedIcons[icon] = nil
	self.MinimapIcons[icon] = nil;
	self.IconsOnEdge[icon] = nil;
	icon:Hide();
	
	local MinimapIconCount = self.MinimapIconCount - 1
	if ( MinimapIconCount <= 0 ) then
		-- no icons left to manage
		self.processingFrame:Hide()
		MinimapIconCount = 0 -- because I'm paranoid
	end
	self.MinimapIconCount = MinimapIconCount
	
	return 0;
end

function Astrolabe:RemoveAllMinimapIcons()
	self:DumpNewIconsCache()
	local MinimapIcons = self.MinimapIcons;
	local IconsOnEdge = self.IconsOnEdge;
	for k, v in pairs(MinimapIcons) do
		MinimapIcons[k] = nil;
		IconsOnEdge[k] = nil;
		k:Hide();
	end
	self.MinimapIconCount = 0
	self.processingFrame:Hide()
end

local lastZoom; -- to remember the last seen Minimap zoom level

-- local variables to track the status of the two update coroutines
local fullUpdateInProgress = true
local resetIncrementalUpdate = false
local resetFullUpdate = false

-- Incremental Update Code
do
	-- local variables to track the incremental update coroutine
	local incrementalUpdateCrashed = true
	local incrementalUpdateThread
	
	local function UpdateMinimapIconPositions( self )
		yield()
		
		while ( true ) do
			self:DumpNewIconsCache() -- put new/updated icons into the main datacache
			
			resetIncrementalUpdate = false -- by definition, the incremental update is reset if it is here
			
			local M, F, x, y = self:GetCurrentPlayerPosition();
			if ( M and M >= 0 ) then
				local Minimap = Minimap;
				local lastPosition = self.LastPlayerPosition;
				local lM, lF, lx, ly = unpack(lastPosition);
				
				minimapRotationEnabled = GetCVar("rotateMinimap") ~= "0"
				if ( minimapRotationEnabled ) then
					minimapRotationOffset = GetPlayerFacing();
				end
				
				-- check current frame rate
				local numPerCycle = min(50, GetFramerate() * (self.MinimapUpdateMultiplier or 1))
				
				-- check Minimap Shape
				minimapShape = GetMinimapShape and ValidMinimapShapes[GetMinimapShape()];
				
				if ( lM == M and lF == F and lx == x and ly == y ) then
					-- player has not moved since the last update
					if ( lastZoom ~= Minimap:GetZoom() or self.ForceNextUpdate or minimapRotationEnabled ) then
						local currentZoom = Minimap:GetZoom();
						lastZoom = currentZoom;
						local mapWidth = Minimap:GetWidth();
						local mapHeight = Minimap:GetHeight();
						numPerCycle = numPerCycle * 2
						local count = 0
						for icon, data in pairs(self.MinimapIcons) do
							placeIconOnMinimap(Minimap, currentZoom, mapWidth, mapHeight, icon, data.dist, data.xDist, data.yDist);
							
							count = count + 1
							if ( count > numPerCycle ) then
								count = 0
								yield()
								-- check if the incremental update cycle needs to be reset 
								-- because a full update has been run
								if ( resetIncrementalUpdate ) then
									break;
								end
							end
						end
						self.ForceNextUpdate = false;
					end
				else
					local dist, xDelta, yDelta = self:ComputeDistance(lM, lF, lx, ly, M, F, x, y);
					if ( dist ) then
						local currentZoom = Minimap:GetZoom();
						lastZoom = currentZoom;
						local mapWidth = Minimap:GetWidth();
						local mapHeight = Minimap:GetHeight();
						local count = 0
						for icon, data in pairs(self.MinimapIcons) do
							local xDist = data.xDist - xDelta;
							local yDist = data.yDist - yDelta;
							local dist = sqrt(xDist*xDist + yDist*yDist);
							placeIconOnMinimap(Minimap, currentZoom, mapWidth, mapHeight, icon, dist, xDist, yDist);
							
							data.dist = dist;
							data.xDist = xDist;
							data.yDist = yDist;
							
							count = count + 1
							if ( count >= numPerCycle ) then
								count = 0
								yield()
								-- check if the incremental update cycle needs to be reset 
								-- because a full update has been run
								if ( resetIncrementalUpdate ) then
									break;
								end
							end
						end
						if not ( resetIncrementalUpdate ) then
							lastPosition[1] = M;
							lastPosition[2] = F;
							lastPosition[3] = x;
							lastPosition[4] = y;
						end
					else
						self:RemoveAllMinimapIcons()
						lastPosition[1] = M;
						lastPosition[2] = F;
						lastPosition[3] = x;
						lastPosition[4] = y;
					end
				end
			else
				if not ( self.WorldMapVisible ) then
					self.processingFrame:Hide();
				end
			end
			
			-- if we've been reset, then we want to start the new cycle immediately
			if not ( resetIncrementalUpdate ) then
				yield()
			end
		end
	end
	
	function Astrolabe:UpdateMinimapIconPositions()
		if ( fullUpdateInProgress ) then
			-- if we're in the middle a a full update, we want to finish that first
			self:CalculateMinimapIconPositions()
		else
			if ( incrementalUpdateCrashed ) then
				incrementalUpdateThread = coroutine.wrap(UpdateMinimapIconPositions)
				incrementalUpdateThread(self) --initialize the thread
			end
			incrementalUpdateCrashed = true
			incrementalUpdateThread()
			incrementalUpdateCrashed = false
		end
	end
end

-- Full Update Code
do
	-- local variables to track the full update coroutine
	local fullUpdateCrashed = true
	local fullUpdateThread
	
	local function CalculateMinimapIconPositions( self )
		yield()
		
		while ( true ) do
			self:DumpNewIconsCache() -- put new/updated icons into the main datacache
			
			resetFullUpdate = false -- by definition, the full update is reset if it is here
			fullUpdateInProgress = true -- set the flag the says a full update is in progress
			
			local M, F, x, y = self:GetCurrentPlayerPosition();
			if ( M and M >= 0 ) then
				minimapRotationEnabled = GetCVar("rotateMinimap") ~= "0"
				if ( minimapRotationEnabled ) then
					minimapRotationOffset = GetPlayerFacing();
				end
				
				-- check current frame rate
				local numPerCycle = GetFramerate() * (self.MinimapUpdateMultiplier or 1) * 2
				
				-- check Minimap Shape
				minimapShape = GetMinimapShape and ValidMinimapShapes[GetMinimapShape()];
				
				local currentZoom = Minimap:GetZoom();
				lastZoom = currentZoom;
				local Minimap = Minimap;
				local mapWidth = Minimap:GetWidth();
				local mapHeight = Minimap:GetHeight();
				local count = 0
				for icon, data in pairs(self.MinimapIcons) do
					local dist, xDist, yDist = self:ComputeDistance(M, F, x, y, data.mapID, data.mapFloor, data.xPos, data.yPos);
					if ( dist ) then
						placeIconOnMinimap(Minimap, currentZoom, mapWidth, mapHeight, icon, dist, xDist, yDist);
						
						data.dist = dist;
						data.xDist = xDist;
						data.yDist = yDist;
					else
						self:RemoveIconFromMinimap(icon)
					end
					
					count = count + 1
					if ( count >= numPerCycle ) then
						count = 0
						yield()
						-- check if we need to restart due to the full update being reset
						if ( resetFullUpdate ) then
							break;
						end
					end
				end
				
				if not ( resetFullUpdate ) then
					local lastPosition = self.LastPlayerPosition;
					lastPosition[1] = M;
					lastPosition[2] = F;
					lastPosition[3] = x;
					lastPosition[4] = y;
					
					resetIncrementalUpdate = true
				end
			else
				if not ( self.WorldMapVisible ) then
					self.processingFrame:Hide();
				end
			end
			
			-- if we've been reset, then we want to start the new cycle immediately
			if not ( resetFullUpdate ) then
				fullUpdateInProgress = false
				yield()
			end
		end
	end
	
	function Astrolabe:CalculateMinimapIconPositions( reset )
		if ( fullUpdateCrashed ) then
			fullUpdateThread = coroutine.wrap(CalculateMinimapIconPositions)
			fullUpdateThread(self) --initialize the thread
		elseif ( reset ) then
			resetFullUpdate = true
		end
		fullUpdateCrashed = true
		fullUpdateThread()
		fullUpdateCrashed = false
		
		-- return result flag
		if ( fullUpdateInProgress ) then
			return 1 -- full update started, but did not complete on this cycle
		
		else
			if ( resetIncrementalUpdate ) then
				return 0 -- update completed
			else
				return -1 -- full update did no occur for some reason
			end
		
		end
	end
end

function Astrolabe:GetDistanceToIcon( icon )
	local data = self.MinimapIcons[icon];
	if ( data ) then
		return data.dist, data.xDist, data.yDist;
	end
end

function Astrolabe:IsIconOnEdge( icon )
	return self.IconsOnEdge[icon];
end

function Astrolabe:GetDirectionToIcon( icon )
	local data = self.MinimapIcons[icon];
	if ( data ) then
		local dir = atan2(data.xDist, -(data.yDist))
		if ( dir > 0 ) then
			return twoPi - dir;
		else
			return -dir;
		end
	end
end

function Astrolabe:Register_OnEdgeChanged_Callback( func, ident )
	-- check argument types
	argcheck(func, 2, "function");
	
	self.IconsOnEdge_GroupChangeCallbacks[func] = ident;
end

--*****************************************************************************
-- INTERNAL USE ONLY PLEASE!!!
-- Calling this function at the wrong time can cause errors
--*****************************************************************************
function Astrolabe:DumpNewIconsCache()
	local MinimapIcons = self.MinimapIcons
	for icon, data in pairs(AddedOrUpdatedIcons) do
		MinimapIcons[icon] = data
		AddedOrUpdatedIcons[icon] = nil
	end
	-- we now need to restart any updates that were in progress
	resetIncrementalUpdate = true
	resetFullUpdate = true
end


--------------------------------------------------------------------------------------------------------------
-- World Map Icon Placement
--------------------------------------------------------------------------------------------------------------

function Astrolabe:PlaceIconOnWorldMap( worldMapFrame, icon, mapID, mapFloor, xPos, yPos )
	-- check argument types
	argcheck(worldMapFrame, 2, "table");
	assert(3, worldMapFrame.GetWidth and worldMapFrame.GetHeight, "Usage Message");
	argcheck(icon, 3, "table");
	assert(3, icon.SetPoint and icon.ClearAllPoints, "Usage Message");
	argcheck(mapID, 4, "number");
	argcheck(mapFloor, 5, "number", "nil");
	argcheck(xPos, 6, "number");
	argcheck(yPos, 7, "number");
	
	local M, F = GetCurrentMapAreaID(), GetCurrentMapDungeonLevel();
	local nX, nY = self:TranslateWorldMapPosition(mapID, mapFloor, xPos, yPos, M, F);
	
	-- anchor and :Show() the icon if it is within the boundry of the current map, :Hide() it otherwise
	if ( nX and nY and (0 < nX and nX <= 1) and (0 < nY and nY <= 1) ) then
		icon:ClearAllPoints();
		icon:SetPoint("CENTER", worldMapFrame, "TOPLEFT", nX * worldMapFrame:GetWidth(), -nY * worldMapFrame:GetHeight());
		icon:Show();
	else
		icon:Hide();
	end
	return nX, nY;
end


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
		
		-- re-calculate all Minimap Icon positions
		if ( frame:IsVisible() ) then
			self:CalculateMinimapIconPositions(true);
		end
	
	elseif ( event == "PLAYER_LEAVING_WORLD" ) then
		frame:Hide(); -- yes, I know this is redunant
		self:RemoveAllMinimapIcons(); --dump all minimap icons
		-- TODO: when I uncouple the point buffer from Minimap drawing,
		--       I should consider updating LastPlayerPosition here
	
	elseif ( event == "PLAYER_ENTERING_WORLD" ) then
		frame:Show();
		if not ( frame:IsVisible() ) then
			-- do the minimap recalculation anyways if the OnShow script didn't execute
			-- this is done to ensure the accuracy of information about icons that were 
			-- inserted while the Player was in the process of zoning
			self:CalculateMinimapIconPositions(true);
		end
	
	elseif ( event == "ZONE_CHANGED_NEW_AREA" ) then
		frame:Hide();
		frame:Show();
	
	end
end

function Astrolabe:OnUpdate( frame, elapsed )
	-- on-edge group changed call-backs
	if ( self.IconsOnEdgeChanged ) then
		self.IconsOnEdgeChanged = false;
		for func in pairs(self.IconsOnEdge_GroupChangeCallbacks) do
			pcall(func);
		end
	end
	
	self:UpdateMinimapIconPositions();
end

function Astrolabe:OnShow( frame )
	-- set the world map to a zoom with a valid player position
	if not ( self.WorldMapVisible ) then
		SetMapToCurrentZone();
	end
	local M, F = Astrolabe:GetCurrentPlayerPosition();
	if ( M and M >= 0 ) then
		SetMapByID(M);
		SetDungeonMapLevel(F);
	else
		frame:Hide();
		return
	end
	
	-- re-calculate minimap icon positions (if needed)
	if ( next(self.MinimapIcons) ) then
		self:CalculateMinimapIconPositions(true);
	else
		-- needed so that the cycle doesn't overwrite an updated LastPlayerPosition
		resetIncrementalUpdate = true;
	end
	
	if ( self.MinimapIconCount <= 0 ) then
		-- no icons left to manage
		frame:Hide();
	end
end

function Astrolabe:OnHide( frame )
	-- dump the new icons cache here
	-- a full update will performed the next time processing is re-actived
	self:DumpNewIconsCache()
end

-- called by AstrolabMapMonitor when all world maps are hidden
function Astrolabe:AllWorldMapsHidden()
	if ( IsLoggedIn() ) then
		self.processingFrame:Hide();
		self.processingFrame:Show();
	end
end


--------------------------------------------------------------------------------------------------------------
-- Library Registration
--------------------------------------------------------------------------------------------------------------

local function harvestMapData( HarvestedMapData )
	local mapData = {}
	local mapName = GetMapInfo();
	local C, Z = GetCurrentMapContinent(), GetCurrentMapZone();
	local mapID = GetCurrentMapAreaID();
	local numFloors = GetNumDungeonMapLevels();
	mapData.mapName = mapName;
	mapData.cont = C;
	mapData.zone = Z;
	mapData.numFloors = numFloors;
	local _, TLx, TLy, BRx, BRy = GetCurrentMapZone();
	if ( TLx and TLy and BRx and BRy ) then
		mapData[0] = {};
		if not ( TLx < BRx ) then
			TLx = -TLx;
			BRx = -BRx;
		end
		if not ( TLy < BRy) then
			TLx = -TLx;
			BRx = -BRx;
		end
		mapData[0].TLx = TLx;
		mapData[0].TLy = TLy;
		mapData[0].BRx = BRx;
		mapData[0].BRy = BRy;
	end
	if ( numFloors > 0 ) then
		for f = 1, numFloors do
			SetDungeonMapLevel(f);
			local _, TLx, TLy, BRx, BRy = GetCurrentMapDungeonLevel();
			if ( TLx and TLy and BRx and BRy ) then
				mapData[f] = {};
				if not ( TLx < BRx ) then
					TLx = -TLx;
					BRx = -BRx;
				end
				if not ( TLy < BRy) then
					TLx = -TLx;
					BRx = -BRx;
				end
				mapData[f].TLx = TLx;
				mapData[f].TLy = TLy;
				mapData[f].BRx = BRx;
				mapData[f].BRy = BRy;
			end
		end
	end
	HarvestedMapData[mapID] = mapData;
end

local function activate( newInstance, oldInstance )
	if ( oldInstance ) then -- this is an upgrade activate
		if ( oldInstance.DumpNewIconsCache ) then
			oldInstance:DumpNewIconsCache()
		end
		for k, v in pairs(oldInstance) do
			if ( type(v) ~= "function" and (not configConstants[k]) ) then
				newInstance[k] = v;
			end
		end
		-- sync up the current MinimapIconCount value
		local iconCount = 0
		for _ in pairs(newInstance.MinimapIcons) do
			iconCount = iconCount + 1
		end
		newInstance.MinimapIconCount = iconCount
		
		Astrolabe = oldInstance;
	else
		local frame = CreateFrame("Frame");
		newInstance.processingFrame = frame;
		
		newInstance.HarvestedMapData = {};
		local HarvestedMapData = newInstance.HarvestedMapData;
		
		newInstance.ContinentList = { GetMapContinents() };
		for C in pairs(newInstance.ContinentList) do
			local zones = { GetMapZones(C) };
			newInstance.ContinentList[C] = zones;
			SetMapZoom(C, 0);
			zones[0] = GetCurrentMapAreaID();
			harvestMapData(HarvestedMapData);
			for Z in ipairs(zones) do
				SetMapZoom(C, Z);
				zones[Z] = GetCurrentMapAreaID();
				harvestMapData(HarvestedMapData);
			end
		end
		
		for id=1,10000 do
			if not ( HarvestedMapData[id] ) then
				if ( SetMapByID(id) ) then
					harvestMapData(HarvestedMapData);
				end
			end
		end
	end
	configConstants = nil -- we don't need this anymore
	
	local frame = newInstance.processingFrame;
	frame:Hide();
	frame:SetParent("Minimap");
	frame:UnregisterAllEvents();
	frame:RegisterEvent("MINIMAP_UPDATE_ZOOM");
	frame:RegisterEvent("PLAYER_LEAVING_WORLD");
	frame:RegisterEvent("PLAYER_ENTERING_WORLD");
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
	frame:SetScript("OnEvent",
		function( frame, event, ... )
			Astrolabe:OnEvent(frame, event, ...);
		end
	);
	frame:SetScript("OnUpdate",
		function( frame, elapsed )
			Astrolabe:OnUpdate(frame, elapsed);
		end
	);
	frame:SetScript("OnShow",
		function( frame )
			Astrolabe:OnShow(frame);
		end
	);
	frame:SetScript("OnHide",
		function( frame )
			Astrolabe:OnHide(frame);
		end
	);
	
	setmetatable(Astrolabe.MinimapIcons, MinimapIconsMetatable)
end

DongleStub:Register(Astrolabe, activate)


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

ValidMinimapShapes = {
	-- { upper-left, lower-left, upper-right, lower-right }
	["SQUARE"]                = { false, false, false, false },
	["CORNER-TOPLEFT"]        = { true,  false, false, false },
	["CORNER-TOPRIGHT"]       = { false, false, true,  false },
	["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
	["CORNER-BOTTOMRIGHT"]    = { false, false, false, true },
	["SIDE-LEFT"]             = { true,  true,  false, false },
	["SIDE-RIGHT"]            = { false, false, true,  true },
	["SIDE-TOP"]              = { true,  false, true,  false },
	["SIDE-BOTTOM"]           = { false, true,  false, true },
	["TRICORNER-TOPLEFT"]     = { true,  true,  true,  false },
	["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true },
	["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true },
	["TRICORNER-BOTTOMRIGHT"] = { false, true,  true,  true },
}

-- distances across and offsets of the world maps
-- in game yards
WorldMapSize = {
	[0] = {
		height = 31809.52239642751,
		parent = 0,
		system = 0,
		width = 47714.28684972192,
		[13] = {
			xOffset = -8476.1894007627,
			yOffset = -18428.57031019741,
		},
		[14] = {
			xOffset = -36714.28737618004,
			yOffset = -14761.90436382772,
		},
		[485] = {
			xOffset = -25238.09554293004,
			yOffset = -11047.61835324072,
		},
	},
	[4] = {
		parent = 13,
	},
	[9] = {
		parent = 13,
	},
	[11] = {
		parent = 13,
	},
	[13] = {
		height = 24533.19943776332,
		parent = 0,
		system = 13,
		width = 36799.81248703782,
		xOffset = -17066.60153393492,
		yOffset = -12799.89960652374,
	},
	[14] = {
		height = 27149.68748093322,
		parent = 0,
		system = 14,
		width = 40741.17907455011,
		xOffset = -18171.96844285111,
		yOffset = -11176.34366519442,
	},
	[16] = {
		parent = 14,
	},
	[17] = {
		parent = 14,
	},
	[19] = {
		parent = 14,
	},
	[20] = {
		parent = 14,
	},
	[21] = {
		parent = 14,
	},
	[22] = {
		parent = 14,
	},
	[23] = {
		parent = 14,
	},
	[24] = {
		parent = 14,
	},
	[26] = {
		parent = 14,
	},
	[27] = {
		parent = 14,
	},
	[28] = {
		parent = 14,
	},
	[29] = {
		parent = 14,
	},
	[30] = {
		parent = 14,
	},
	[32] = {
		parent = 14,
	},
	[34] = {
		parent = 14,
	},
	[35] = {
		parent = 14,
	},
	[36] = {
		parent = 14,
	},
	[37] = {
		parent = 14,
	},
	[38] = {
		parent = 14,
	},
	[39] = {
		parent = 14,
	},
	[40] = {
		parent = 14,
	},
	[41] = {
		parent = 13,
	},
	[42] = {
		parent = 13,
	},
	[43] = {
		parent = 13,
	},
	[61] = {
		parent = 13,
	},
	[81] = {
		parent = 13,
	},
	[101] = {
		parent = 13,
	},
	[121] = {
		parent = 13,
	},
	[141] = {
		parent = 13,
	},
	[161] = {
		parent = 13,
	},
	[181] = {
		parent = 13,
	},
	[182] = {
		parent = 13,
	},
	[201] = {
		parent = 13,
	},
	[241] = {
		parent = 13,
	},
	[261] = {
		parent = 13,
	},
	[281] = {
		parent = 13,
	},
	[301] = {
		parent = 14,
	},
	[321] = {
		[1] = {
			height = 1159.58349609375,
			width = 1739.375,
			xOffset = 3506.35400390625,
			yOffset = -2486.666748046875,
		},
		[2] = {
			height = 241.3902501271251,
			width = 362.0896285198292,
			xOffset = 4163.967214776516,
			yOffset = -1932.2718269577,
		},
		parent = 13,
		xOffset = 8690.027273370266,
		yOffset = -3623.151831840512,
	},
	[341] = {
		parent = 14,
	},
	[362] = {
		parent = 13,
	},
	[381] = {
		parent = 13,
	},
	[382] = {
		parent = 14,
	},
	[462] = {
		height = 3283.332957514876,
		parent = 14,
		width = 4924.999347356147,
		xOffset = 2087.500228882575,
		yOffset = -8641.665775769438,
	},
	[463] = {
		height = 2200.000100524817,
		parent = 14,
		width = 3300.000849582923,
		xOffset = 2883.332724962417,
		yOffset = -5866.66614274571,
	},
	[464] = {
		height = 2714.581332796625,
		parent = 13,
		width = 4070.830338460461,
		xOffset = -7099.99863117853,
		yOffset = -7339.582330574734,
	},
	[465] = {
		parent = 466,
	},
	[466] = {
		height = 11642.7184306688,
		parent = 466,
		system = 466,
		width = 17464.0778976456,
		xOffset = -12996.039023266,
		yOffset = -5821.359136647918,
	},
	[467] = {
		parent = 466,
	},
	[471] = {
		height = 704.6879439334424,
		parent = 13,
		width = 1056.769917572753,
		xOffset = -6533.632539833583,
		yOffset = -6523.649952411448,
	},
	[473] = {
		parent = 466,
	},
	[475] = {
		parent = 466,
	},
	[476] = {
		height = 2174.99908042674,
		parent = 13,
		width = 3262.500356655771,
		xOffset = -7525.000166381135,
		yOffset = -9374.999432854662,
	},
	[477] = {
		parent = 466,
	},
	[478] = {
		parent = 466,
	},
	[479] = {
		parent = 466,
	},
	[480] = {
		height = 806.7718973194787,
		parent = 14,
		width = 1211.45871108373,
		xOffset = 4000.749319189492,
		yOffset = -7753.709392183317,
	},
	[481] = {
		parent = 466,
	},
	[485] = {
		height = 11834.2651530051,
		parent = 0,
		system = 485,
		width = 17751.39838591091,
		xOffset = -9217.152309900695,
		yOffset = -10593.37486945282,
	},
	[486] = {
		parent = 485,
	},
	[488] = {
		parent = 485,
	},
	[490] = {
		parent = 485,
	},
	[491] = {
		parent = 485,
	},
	[492] = {
		parent = 485,
	},
	[493] = {
		parent = 485,
	},
	[495] = {
		parent = 485,
	},
	[496] = {
		parent = 485,
	},
	[499] = {
		height = 2218.750266591503,
		parent = 14,
		width = 3327.083620018369,
		xOffset = 2902.082335154929,
		yOffset = -11168.74964634414,
	},
	[501] = {
		parent = 485,
	},
	[504] = {
		[1] = {
			height = 553.3399540907861,
			width = 830.0164284077179,
			xOffset = -1052.511094552897,
			yOffset = -6066.67114818645,
		},
		[2] = {
			height = 375.4892662605064,
			width = 563.2227893164886,
			xOffset = -915.86865482248,
			yOffset = -5975.332586681272,
		},
		parent = 485,
		xOffset = -1270.795998074708,
		yOffset = -11581.5767723675,
	},
	[510] = {
		parent = 485,
	},
	[541] = {
		parent = 485,
	},
	[544] = {
		parent = 544,
	},
	[605] = {
		parent = 605,
	},
	[606] = {
		parent = 13,
	},
	[607] = {
		parent = 13,
	},
	[610] = {
		parent = 14,
	},
	[613] = {
		parent = 14,
	},
	[614] = {
		parent = 14,
	},
	[615] = {
		parent = 14,
	},
	[640] = {
		parent = 640,
	},
	[673] = {
		parent = 14,
	},
	[684] = {
		parent = 14,
	},
	[685] = {
		parent = 14,
	},
	[689] = {
		parent = 14,
	},
	[700] = {
		parent = 14,
	},
	[708] = {
		height = 1343.750015102286,
		parent = 14,
		width = 2014.581529778917,
		xOffset = -4810.415836184278,
		yOffset = 2160.41647470917,
	},
	[709] = {
		height = 1224.999536483739,
		parent = 14,
		width = 1837.49974069494,
		xOffset = -5212.499704174925,
		yOffset = 1222.91665807089,
	},
	[720] = {
		parent = 13,
	},
	[737] = {
		parent = 737,
	},
	[772] = {
		parent = 13,
	},
}

zeroData = { xOffset = 0, height = 0, yOffset = 0, width = 0, __index = function() return zeroData end };
setmetatable(zeroData, zeroData);

function printError( ... )
	if ( ASTROLABE_VERBOSE) then
		print(...)
	end
end

for mapID, harvestedData in pairs(Astrolabe.HarvestedMapData) do
	local mapData = WorldMapSize[mapID];
	if ( mapData ) then
		if not ( mapData.system ) then
			mapData.system = mapData.parent;
		end
		setmetatable(mapData, zeroData);
		if ( harvestedData.numFloors > 0 ) then
			for f, harvData in pairs(harvestedData) do
				if ( type(f) == "number" and f > 0 ) then
					if not ( mapData[f] ) then
						mapData[f] = {};
					end
					local floorData = mapData[f]
					if not ( floorData.width ) then
						floorData.width = harvData.BRx - harvData.TLx
					end
					if not ( floorData.height ) then
						floorData.height = harvData.BRy - harvData.TLy
					end
					if not ( floorData.xOffset ) then
						floorData.xOffset = harvData.TLx
					end
					if not ( floorData.yOffset ) then
						floorData.yOffset = harvData.TLy
					end
				end
			end
			for f = 1, harvestedData.numFloors do
				if not ( mapData[f] ) then
					mapData[f] = zeroData;
				end
			end
			-- TODO: handle floored world maps
		
		else
			local harvData = harvestedData[0]
			if not ( mapData.width ) then
				mapData.width = harvData.BRx - harvData.TLx
			end
			if not ( mapData.height ) then
				mapData.height = harvData.BRy - harvData.TLy
			end
			if not ( mapData.xOffset ) then
				mapData.xOffset = harvData.TLx
			end
			if not ( mapData.yOffset ) then
				mapData.yOffset = harvData.TLy
			end
		
		end
	
	else
		if ( harvestedData.cont > 0 ) then
			printError(("Astrolabe is missing data for world map %s [%d] (%d, %d)."):format(harvestedData.mapName, mapID, harvestedData.cont, harvestedData.zone));
		end
		local mapData = {};
		WorldMapSize[mapID] = mapData;
		setmetatable(mapData, zeroData);
		
		mapData.parent = mapID;
		if ( harvestedData.cont > 0 and harvestedData.zone > 0 ) then
			mapData.parent = Astrolabe:GetMapID(harvestedData.cont, nil);
		end
		mapData.system = mapData.parent;
		if ( harvestedData.numFloors > 0 ) then
			for f, harvData in pairs(harvestedData) do
				if ( type(f) == "number" and f > 0 ) then
					mapData[f] = {};
					local floorData = mapData[f]
					floorData.width = harvData.BRx - harvData.TLx
					floorData.height = harvData.BRy - harvData.TLy
					floorData.xOffset = harvData.TLx
					floorData.yOffset = harvData.TLy
				end
			end
			for f = 1, harvestedData.numFloors do
				if not ( mapData[f] ) then
					mapData[f] = zeroData;
					printError(("Astrolabe is missing data for %s [%d], floor %d."):format(harvestedData.mapName, mapID, f));
				end
			end
		
		else
			local harvData = harvestedData[0]
			if ( harvData ) then
				mapData.width = harvData.BRx - harvData.TLx
				mapData.height = harvData.BRy - harvData.TLy
				mapData.xOffset = harvData.TLx
				mapData.yOffset = harvData.TLy
			
			else
				WorldMapSize[mapID] = zeroData;
				printError(("Astrolabe is missing data for %s [%d]."):format(harvestedData.mapName, mapID));
			
			end
		
		end
	
	end
end

setmetatable(WorldMapSize, zeroData);

-- register this library with AstrolabeMapMonitor, this will cause a full update if PLAYER_LOGIN has already fired
local AstrolabeMapMonitor = DongleStub("AstrolabeMapMonitor");
AstrolabeMapMonitor:RegisterAstrolabeLibrary(Astrolabe, LIBRARY_VERSION_MAJOR);
