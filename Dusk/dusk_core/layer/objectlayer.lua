--------------------------------------------------------------------------------
--[[
Dusk Engine Component: Object Layer

Builds an object layer from data.
--]]
--------------------------------------------------------------------------------

local lib_objectlayer = {}

--------------------------------------------------------------------------------
-- Localize
--------------------------------------------------------------------------------
local require = require

local verby = require("Dusk.dusk_core.external.verby")
local screen = require("Dusk.dusk_core.misc.screen")
local lib_settings = require("Dusk.dusk_core.misc.settings")
local lib_functions = require("Dusk.dusk_core.misc.functions")

local display_newGroup = display.newGroup
local display_newCircle = display.newCircle
local display_newRect = display.newRect
local display_newLine = display.newLine
local display_newSprite = display.newSprite
local display_remove = display.remove
local string_len = string.len
local math_max = math.max
local math_min = math.min
local math_huge = math.huge
local math_nhuge = -math_huge
local math_ceil = math.ceil
local table_insert = table.insert
local table_maxn = table.maxn
local type = type
local unpack = unpack
local verby_error = verby.error
local verby_alert = verby.alert
local physics_addBody; if physics and type(physics) == "table" and physics.addBody then physics_addBody = physics.addBody else physics_addBody = function() verby_error("Physics library was not found on Dusk Engine startup") end end
local getSetting = lib_settings.get
local spliceTable = lib_functions.spliceTable
local isPolyClockwise = lib_functions.isPolyClockwise
local reversePolygon = lib_functions.reversePolygon
local getProperties = lib_functions.getProperties
local setProperty = lib_functions.setProperty
local rotatePoint = lib_functions.rotatePoint
local physicsKeys = {radius = true, isSensor = true, bounce = true, friction = true, density = true, shape = true}

--------------------------------------------------------------------------------
-- Create Layer
--------------------------------------------------------------------------------
function lib_objectlayer.createLayer(map, mapData, data, dataIndex, tileIndex, imageSheets, imageSheetConfig)
	local dotImpliesTable = getSetting("dotImpliesTable")
	local ellipseRadiusMode = getSetting("ellipseRadiusMode")
	local styleObj = getSetting("styleObject")
	local styleEllipse = getSetting("styleEllipseObject")
	local stylePointBased = getSetting("stylePointBasedObject")
	local styleImageObj = getSetting("styleImageObject")
	local styleRect = getSetting("styleRectObject")
	local autoGenerateObjectShapes = getSetting("autoGenerateObjectPhysicsShapes")
	local objectsDefaultToData = getSetting("objectsDefaultToData")
	local virtualObjectsVisible = getSetting("virtualObjectsVisible")
	local objTypeRectPointSquare = getSetting("objTypeRectPointSquare")
	local gridScale = getSetting("objectCullingGridScale")

	local layerProps = getProperties(data.properties or {}, "objects", true)

	local layer = display_newGroup()
	layer.props = {}
	layer._layerType = "object"
	layer.object = {}

	local objDatas = {}

	local cullingGrid = {}
	local tileWidth, tileHeight

	local prepareCulling = function() tileWidth, tileHeight = map.data.tileWidth, map.data.tileHeight end
	local pixelsToCullingGrid = function(x, y) return math_ceil(x / tileWidth), math_ceil(y / tileHeight) end
	local makeCullingGridEntry = function() return {lt = {}, rt = {}, lb = {}, rb = {}} end

	-- Get object bounds for culling grid
	local getObjectDataBounds = function(objData)
		if objData.type == "ellipse" or objData.type == "rect" or objData.type == "image" then
			objData.bounds.xMin = objData.transfer.x - objData.width * 0.5
			objData.bounds.xMax = objData.transfer.x + objData.width * 0.5
			objData.bounds.yMin = objData.transfer.y - objData.height * 0.5
			objData.bounds.yMax = objData.transfer.y + objData.height * 0.5
		elseif objData.type == "polywhatsit" then
			objData.bounds.xMin = objData.xMin + objData.transfer.x
			objData.bounds.xMax = objData.xMax + objData.transfer.x
			objData.bounds.yMin = objData.yMin + objData.transfer.y
			objData.bounds.yMax = objData.yMax + objData.transfer.y
		end
	end

	------------------------------------------------------------------------------
	-- Add Object Data to Culling Grid
	------------------------------------------------------------------------------
	local addObjectDataToCullingGrid = function(objData)
		local l, t = pixelsToCullingGrid(objData.bounds.xMin, objData.bounds.yMin)
		local r, b = pixelsToCullingGrid(objData.bounds.xMax, objData.bounds.yMax)

		cullingGrid[l] = cullingGrid[l] or {}
		cullingGrid[r] = cullingGrid[r] or {}

		cullingGrid[l][t] = cullingGrid[l][t] or makeCullingGridEntry()
		cullingGrid[r][t] = cullingGrid[r][t] or makeCullingGridEntry()
		cullingGrid[l][b] = cullingGrid[l][b] or makeCullingGridEntry()
		cullingGrid[r][b] = cullingGrid[r][b] or makeCullingGridEntry()

		table_insert(cullingGrid[l][t].lt, objData)
		table_insert(cullingGrid[r][t].rt, objData)
		table_insert(cullingGrid[l][b].lb, objData)
		table_insert(cullingGrid[r][b].rb, objData)
	end

	local cullObject = function(objData)
		display.remove(objData.constructedObject)
		objData.constructedObject = nil
	end

	------------------------------------------------------------------------------
	-- Construct Object (from processed object data)
	------------------------------------------------------------------------------
	local constructObject = function(objData)
		local obj

		if not objData.isDataObject then
			if objData.type == "ellipse" then
				obj = display_newCircle(0, 0, objData.radius)
				
				styleEllipse(obj)
			elseif objData.type == "polywhatsit" then
				local points = objData.points

				obj = display_newLine(points[1].x, points[1].y, points[2].x, points[2].y)
				for i = 3, #points do obj:append(points[i].x, points[i].y) end
				if objData.closed then obj:append(points[1].x, points[1].y) end
			
				obj.points = objData.points
				stylePointBased(obj)
			elseif objData.type == "image" then
				local tileData = objData.tileData
				local sheetIndex = tileData.tilesetIndex
				local tileGID = tileData.gid

				obj = display_newSprite(imageSheets[sheetIndex], imageSheetConfig[sheetIndex])
				obj:setFrame(tileGID)

				styleImageObj(obj)
			elseif objData.type == "rect" then
				obj = display_newRect(0, 0, objData.width, objData.height)

				styleRect(obj)
			end

			layer:insert(obj)
		else
			if objData.type == "ellipse" then
				obj = {radius = objData.radius}
			elseif objData.type == "polywhatsit" then
				obj = {points = objData.points}
			elseif objData.type == "image" then
				obj = {tileData = objData.tileData}
			else
				obj = {width = objData.width, height = objData.height}
			end
		end

		for k, v in pairs(objData.transfer) do
			obj[k] = v
		end

		if objData.physicsExistent then
			if #data.physicsParameters == 1 then
				physics_addBody(obj, objData.physicsParameters[1])
			else
				physics_addBody(obj, unpack(objData.physicsParameters))
			end
		end

		objData.constructedObject = obj
	end

	------------------------------------------------------------------------------
	-- Construct Object Data
	------------------------------------------------------------------------------
	local constructObjectData = function(o)
		local data = {
			type = "",
			transfer = {props = {}},
			bounds = {
				xMin = math_huge,
				xMax = math_nhuge,
				yMin = math_huge,
				yMax = math_nhuge
			}
		}
		
		local objProps = getProperties(o.properties or {}, "object", false)
		local physicsExistent = objProps.options.physicsExistent
		if physicsExistent == nil then physicsExistent = layerProps.options.physicsExistent end

		local isDataObject
		if objProps["!isData!"] ~= nil then
			isDataObject = objProps["!isData!"]
		elseif layerProps["!isData!"] ~= nil then
			isDataObject = layerProps["!isData!"]
		else
			isDataObject = objectsDefaultToData
		end

		data.physicsExistent = physicsExistent
		data.isDataObject = isDataObject

		-- Ellipse
		if o.ellipse then
			data.type = "ellipse"
			data.transfer._objType = "ellipse"

			local zx, zy, zw, zh = o.x, o.y, o.width, o.height

			if zw > zh then
				data.radius = zw * 0.5
				data.transfer.yScale = zh / zw
				data.transfer.x = zx + data.radius
				data.transfer.y = zy + data.radius * data.transfer.yScale
			else
				data.radius = zh * 0.5
				data.transfer.xScale = zw / zh
				data.transfer.x = zx + data.radius * data.transfer.xScale
				data.transfer.y = zy + data.radius
			end

			data.width, data.height = zw, zh

			if o.rotation ~= 0 then
				local cornerX, cornerY = zx, zy
				local rX, rY = rotatePoint(zw * 0.5, zh * 0.5, o.rotation or 0)
				data.transfer.x, data.transfer.y = rX + cornerX, rY + cornerY
				data.transfer.rotation = o.rotation
			end

			if autoGenerateObjectShapes and physicsExistent then
				if ellipseRadiusMode == "min" then
					objProps.physics[1].radius = math_min(zw * 0.5, zh * 0.5) -- Min radius
				elseif ellipseRadiusMode == "max" then
					objProps.physics[1].radius = math_max(zw * 0.5, zh * 0.5) -- Max radius
				elseif ellipseRadiusMode == "average" then
					objProps.physics[1].radius = ((zw * 0.5) + (zh * 0.5)) * 0.5 -- Average radius
				end
			end
		-- Polygon, polyline
		elseif o.polygon or o.polyline then
			data.type = "polywhatsit"
			data.transfer._objType = o.polygon and "polygon" or "polyline"
			
			local xMin, yMin, xMax, yMax = math_huge, math_huge, math_nhuge, math_nhuge
			local points = o.polygon or o.polyline
			
			for i = 1, #points do
				if points[i].x < xMin then
					xMin = points[i].x
				elseif points[i].x > xMax then
					xMax = points[i].x
				end

				if points[i].y < yMin then
					yMin = points[i].y
				elseif points[i].y > yMax then
					yMax = points[i].y
				end
			end

			data.xMin, data.yMin, data.xMax, data.yMax = xMin, yMin, xMax, yMax
			data.points = points

			data.transfer.x, data.transfer.y = o.x, o.y

			if o.polygon then data.closed = true end -- Just add a `closed` property so we can keep the name "polywhatsit" for joy and gladness

			if autoGenerateObjectShapes and physicsExistent then
				local physicsShape = {}
				for i = 1, math_min(#points, 8) do
					physicsShape[#physicsShape + 1] = points[i].x
					physicsShape[#physicsShape + 1] = points[i].y
				end

				if not isPolyClockwise(physicsShape) then
					physicsShape = reversePolygon(physicsShape)
				end

				objProps.physics[1].shape = physicsShape
			end
		-- Tile image
		elseif o.gid then
			data.type = "image"
			data.transfer._objType = "image"
			data.tileData = tileIndex[o.gid]
			data.transfer.x, data.transfer.y = o.x + mapData.stats.tileWidth * 0.5, o.y - mapData.stats.tileHeight * 0.5
			data.width, data.height = tileWidth, tileHeight
		-- Rectangle
		else
			data.type = "rect"
			data.transfer._objType = "rect"

			data.width, data.height = o.width, o.height
			
			data.transfer.x = o.x + o.width * 0.5
			data.transfer.y = o.y + o.height * 0.5
			
			if o.rotation ~= 0 then
				local cornerX, cornerY = o.x, o.y
				local rX, rY = rotatePoint(o.width * 0.5, o.height * 0.5, o.rotation or 0)
				data.transfer.x, data.transfer.y = rX + cornerX, rY + cornerY
				data.transfer.rotation = o.rotation
			end
		end

		data.transfer._name = o.name
		data.transfer._type = o.type
		if not isDataObject then
			data.transfer.isVisible = virtualObjectsVisible
		end

		for k, v in pairs(layerProps.object) do if (dotImpliesTable or layerProps.options.usedot[k]) and not layerProps.options.nodot[k] then setProperty(objData.transfer, k, v) else objData.transfer[k] = v end end
		for k, v in pairs(objProps.object) do if (dotImpliesTable or objProps.options.usedot[k]) and not objProps.options.nodot[k] then setProperty(objData.transfer, k, v) else objData.transfer[k] = v end end
		for k, v in pairs(objProps.props) do if (dotImpliesTable or objProps.options.usedot[k]) and not objProps.options.nodot[k] then setProperty(objData.transfer.props, k, v) else objData.transfer.props[k] = v end end

		-- Physics data
		if physicsExistent then
			local physicsParameters = {}
			local physicsBodyCount = layerProps.options.physicsBodyCount
			local tpPhysicsBodyCount = objProps.options.physicsBodyCount; if tpPhysicsBodyCount == nil then tpPhysicsBodyCount = physicsBodyCount end

			physicsBodyCount = math_max(physicsBodyCount, tpPhysicsBodyCount)

			for i = 1, physicsBodyCount do
				physicsParameters[i] = spliceTable(physicsKeys, objProps.physics[i] or {}, layerProps.physics[i] or {})
			end

			data.physicsParameters = physicsParameters
		end

		if o.rotation == 0 then
			getObjectDataBounds(data)
			addObjectDataToCullingGrid(data)
		else
			-- Currently can't do rotated objects because of manual bounds calculation
			verby_alert("Warning: Object rotation is not 0; object will not be added to culling grid or culled.")
			constructObject(data)
		end

		return data
	end

	------------------------------------------------------------------------------
	-- Draw
	------------------------------------------------------------------------------
	function layer.draw(x1, x2, y1, y2)
		if x1 > x2 then x1, x2 = x2, x1 end
		if y1 > y2 then y1, y2 = y2, y1 end

		for x = x1, x2 do
			if cullingGrid[x] then
				for y = y1, y2 do
					if cullingGrid[x][y] then
						local c = cullingGrid[x][y]

						for i = 1, #c.rt do if not c.rt[i].constructedObject then constructObject(c.rt[i]) end end
						for i = 1, #c.lt do if not c.lt[i].constructedObject then constructObject(c.lt[i]) end end
						for i = 1, #c.rb do if not c.rb[i].constructedObject then constructObject(c.rb[i]) end end
						for i = 1, #c.lb do if not c.lb[i].constructedObject then constructObject(c.lb[i]) end end
					end
				end
			end
		end
	end

	------------------------------------------------------------------------------
	-- Erase
	------------------------------------------------------------------------------
	function layer.erase(x1, x2, y1, y2, dir)
		if x1 > x2 then x1, x2 = x2, x1 end
		if y1 > y2 then y1, y2 = y2, y1 end

		for x = x1, x2 do
			if cullingGrid[x] then
				for y = y1, y2 do
					if cullingGrid[x][y] then
						local c = cullingGrid[x][y]

						if dir == "r" and (#c.rt > 0 or #c.rb > 0) then
							for i = 1, #c.rt do if c.rt[i].constructedObject then cullObject(c.rt[i]) end end
							for i = 1, #c.rb do if c.rb[i].constructedObject then cullObject(c.rb[i]) end end
						elseif dir == "l" and (#c.lt > 0 or #c.lb > 0) then
							for i = 1, #c.lt do if c.lt[i].constructedObject then cullObject(c.lt[i]) end end
							for i = 1, #c.lb do if c.lb[i].constructedObject then cullObject(c.lb[i]) end end
						elseif dir == "u" and (#c.rt > 0 or #c.lt > 0) then
							for i = 1, #c.rt do if c.rt[i].constructedObject then cullObject(c.rt[i]) end end
							for i = 1, #c.lt do if c.lt[i].constructedObject then cullObject(c.lt[i]) end end
						elseif dir == "d" and (#c.rb > 0 or #c.lb > 0) then
							for i = 1, #c.rb do if c.rb[i].constructedObject then cullObject(c.rb[i]) end end
							for i = 1, #c.lb do if c.lb[i].constructedObject then cullObject(c.lb[i]) end end
						end
					end
				end
			end
		end
	end

	------------------------------------------------------------------------------
	-- Build All Objects
	------------------------------------------------------------------------------
	function layer._buildAllObjects()
		prepareCulling()
		for i = 1, #data.objects do
			local o = data.objects[i]
			if o == nil then verby_error("Object data missing at index " .. i) end
			objDatas[i] = constructObjectData(o)
		end
	end

	------------------------------------------------------------------------------
	-- Object Iterator Template
	------------------------------------------------------------------------------
	function layer._newIterator(condition, inTable)
		if not inTable then
			local objects = {}

			for i = 1, table_maxn(layer.object) do
				if layer.object[i] and condition(layer.object[i]) then
					table_insert(objects, {index = i})
				end
			end

			local index = 0

			return function()
				index = index + 1
				if objects[index] then
					return layer.object[objects[index].index]
				else
					return nil
				end
			end
		elseif inTable then
			local objects = {}

			for i = 1, table_maxn(layer.object) do
				if layer.object[i] and condition(layer.object[i]) then
					table_insert(objects, layer.object[i])
				end
			end

			return objects
		end
	end

	------------------------------------------------------------------------------
	-- Iterator: _literalIterator()
	------------------------------------------------------------------------------
	function layer._literalIterator(n, checkFor, inTable)
		if not (n ~= nil) then verby_error("Nothing was passed to constructor of literal-match iterator") end

		local n = n
		local checkFor = checkFor or "type"

		return layer._newIterator(function(obj) return obj[checkFor] == n end, inTable)
	end

	------------------------------------------------------------------------------
	-- Iterator: _matchIterator()
	------------------------------------------------------------------------------
	function layer._matchIterator(n, checkFor, inTable)
		if not (n ~= nil) then verby_error("Nothing was passed to constructor of pattern-based iterator") end

		local n = n
		local checkFor = checkFor or "type"

		return layer._newIterator(function(obj) return obj[checkFor]:match(n) ~= nil end, inTable)
	end

	------------------------------------------------------------------------------
	-- Iterators
	------------------------------------------------------------------------------
	-- nameIs()
	function layer.nameIs(n, inTable) return layer._literalIterator(n, "_name", inTable) end
	-- nameMatches()
	function layer.nameMatches(n, inTable) return layer._matchIterator(n, "_name", inTable) end
	-- typeIs()
	function layer.typeIs(n, inTable) return layer._literalIterator(n, "_type", inTable) end
	-- typeMatches()
	function layer.typeMatches(n, inTable) return layer._matchIterator(n, "_type", inTable) end
	-- objTypeIs()
	function layer.objTypeIs(n, inTable) return layer._literalIterator(n, "_objType", inTable) end
	-- objects()
	function layer.objects(inTable) return layer._newIterator(function() return true end, inTable) end

	------------------------------------------------------------------------------
	-- Destroy Layer
	------------------------------------------------------------------------------
	function layer.destroy()
		display_remove(layer)
		layer = nil
	end

	------------------------------------------------------------------------------
	-- Finish Up
	------------------------------------------------------------------------------
	for k, v in pairs(layerProps.props) do if (dotImpliesTable or layerProps.options.usedot[k]) and not layerProps.options.nodot[k] then setProperty(layer.props, k, v) else layer.props[k] = v end end
	for k, v in pairs(layerProps.layer) do if (dotImpliesTable or layerProps.options.usedot[k]) and not layerProps.options.nodot[k] then setProperty(layer, k, v) else layer[k] = v end end

	return layer
end

return lib_objectlayer