--[[
Name: Astrolabe
Revision: $Rev$
Date: $Date$
Id: $Id$
Author(s): Esamynn (jcarrothers@gmail.com)
Inspired By: <Other Project> by <Other Author> (Other Author's email address)
Website: <http://link.to.recent.version/here>
Documentation: <http://link.to.documentation/here>
SVN: <svn://link.to.svn/project/here>
Description: <Short description
    of your library, what it
    does, etc.>
]]

local LIBRARY_VERSION_MAJOR = "Astrolabe"
local LIBRARY_VERSION_MINOR = "$Revision$"

local _G = getfenv(0)
local previous = _G[LIBRARY_VERSION_MAJOR]
if previous and not previous:IsNewVersion(LIBRARY_VERSION_MAJOR, LIBRARY_VERSION_MINOR) then return end


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

WorldMapSize = {
	-- World Map of Azeroth
	[0] = {
		[1] = ,
		[2] = ,
	},
	-- Kalimdor
	[1] = {
		
	},
	-- Eastern Kingdoms
	[2] = {
		
	},
}