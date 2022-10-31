--[[
   Converters for standard Roblox types 
   https://create.roblox.com/docs/reference/engine/datatypes
]]

local EMPTY_VEC3 = Vector3.zero
local EMPTY_V3I16 = Vector3int16.new(0,0,0)
local EMPTY_VEC2 = Vector2.zero
local EMPTY_V2I16 = Vector2int16.new(0,0)
local EMPTY_UDIM = UDim.new(0,0)
local EMPTY_UDIM2 = UDim2.new(0, 0, 0, 0)
local EMPTY_C3 = Color3.fromRGB(0,0,0)
local EMPTY_CS = ColorSequence.new(EMPTY_C3)
local EMPTY_CSK = ColorSequenceKeypoint.new(0,EMPTY_C3)

local Converters = {
	[Vector3] = {
		-- Single
		{
			-- type
			'double[]',
			-- default
			EMPTY_VEC3,
			-- To Serialize
			function (schema, field, value)
				local out = {}

				if typeof(value) ~= 'Vector3' then 
					out[#out+1] = 0
					out[#out+1] = 0
					out[#out+1] = 0
				else
					out[#out+1] = value.X
					out[#out+1] = value.Y
					out[#out+1] = value.Z
				end

				return out
			end, 
			-- To Instance
			function(schema, field, value)
				if value == nil then
					return EMPTY_VEC3
				end
				return Vector3.new(value[1], value[2], value[3])
			end
		},
		-- Array
		{
			-- type
			'double[]',         
			-- default                              
			{},                                             
			-- To Serialize
			function(schema, field, value)    
				local out = {}

				for _, vec3 in ipairs(value) do
					if typeof(vec3) ~= 'Vector3' then 
						out[#out+1] = 0
						out[#out+1] = 0
						out[#out+1] = 0
					else
						out[#out+1] = vec3.X
						out[#out+1] = vec3.Y
						out[#out+1] = vec3.Z
					end
				end

				return out
			end, 
			-- To Instance         
			function(schema, field, value)      
				local out = {}
				if value == nil or #value == 0 then 
					return out
				end

				for i = 1, #value, 3 do
					out[#out+1] = Vector3.new(value[i], value[i+1], value[i+2])
				end
				return out
			end
		}
	},
	[Vector3int16] = {
		-- Single
		{
			-- type
			'double[]',
			-- default
			EMPTY_V3I16,
			-- To Serialize
			function (schema, field, value)
				local out = {}

				if typeof(value) ~= 'Vector3int16' then 
					out[#out+1] = 0
					out[#out+1] = 0
					out[#out+1] = 0
				else
					out[#out+1] = value.X
					out[#out+1] = value.Y
					out[#out+1] = value.Z
				end

				return out
			end, 
			-- To Instance
			function(schema, field, value)
				if value == nil then
					return EMPTY_V3I16
				end
				return Vector3int16.new(value[1], value[2], value[3])
			end
		},
		-- Array
		{
			-- type
			'double[]',         
			-- default                              
			{},                                             
			-- To Serialize
			function(schema, field, value)    
				local out = {}

				for _, vec3 in ipairs(value) do
					if typeof(vec3) ~= 'Vector3int16' then 
						out[#out+1] = 0
						out[#out+1] = 0
						out[#out+1] = 0
					else
						out[#out+1] = vec3.X
						out[#out+1] = vec3.Y
						out[#out+1] = vec3.Z
					end
				end

				return out
			end, 
			-- To Instance         
			function(schema, field, value)      
				local out = {}
				if value == nil or #value == 0 then 
					return out
				end

				for i = 1, #value, 3 do
					out[#out+1] = Vector3int16.new(value[i], value[i+1], value[i+2])
				end
				return out
			end
		}
	},
	[Vector2] = {
		-- Single
		{
			-- type
			'double[]',
			-- default
			EMPTY_VEC2,
			-- To Serialize
			function (schema, field, value)
				local out = {}

				if typeof(value) ~= 'Vector2' then 
					out[#out+1] = 0
					out[#out+1] = 0
				else
					out[#out+1] = value.X
					out[#out+1] = value.Y
				end

				return out
			end, 
			-- To Instance
			function(schema, field, value)
				if value == nil then
					return EMPTY_VEC2
				end
				return Vector2.new(value[1], value[2])
			end
		},
		-- Array
		{
			-- type
			'double[]',         
			-- default                              
			{},                                             
			-- To Serialize
			function(schema, field, value)    
				local out = {}

				for _, vec2 in ipairs(value) do
					if typeof(vec2) ~= 'Vector2' then 
						out[#out+1] = 0
						out[#out+1] = 0
					else
						out[#out+1] = vec2.X
						out[#out+1] = vec2.Y
					end
				end

				return out
			end, 
			-- To Instance         
			function(schema, field, value)      
				local out = {}
				if value == nil or #value == 0 then 
					return out
				end

				for i = 1, #value, 2 do
					out[#out+1] = Vector2.new(value[i], value[i+1])
				end
				return out
			end
		}
	},
	[Vector2int16] = {
		-- Single
		{
			-- type
			'double[]',
			-- default
			EMPTY_V2I16,
			-- To Serialize
			function (schema, field, value)
				local out = {}

				if typeof(value) ~= 'Vector2int16' then 
					out[#out+1] = 0
					out[#out+1] = 0
				else
					out[#out+1] = value.X
					out[#out+1] = value.Y
				end

				return out
			end, 
			-- To Instance
			function(schema, field, value)
				if value == nil then
					return EMPTY_V2I16
				end
				return Vector2int16.new(value[1], value[2])
			end
		},
		-- Array
		{
			-- type
			'double[]',         
			-- default                              
			{},                                             
			-- To Serialize
			function(schema, field, value)    
				local out = {}

				for _, vec2 in ipairs(value) do
					if typeof(vec2) ~= 'Vector2int16' then 
						out[#out+1] = 0
						out[#out+1] = 0
					else
						out[#out+1] = vec2.X
						out[#out+1] = vec2.Y
					end
				end

				return out
			end, 
			-- To Instance         
			function(schema, field, value)      
				local out = {}
				if value == nil or #value == 0 then 
					return out
				end

				for i = 1, #value, 2 do
					out[#out+1] = Vector2int16.new(value[i], value[i+1])
				end
				return out
			end
		}
	},
	[UDim] = {
		-- Single
		{
			-- type
			'double[]',
			-- default
			EMPTY_UDIM,
			-- To Serialize
			function (schema, field, value)
				local out = {}

				if typeof(value) ~= 'UDim' then 
					out[#out+1] = 0
					out[#out+1] = 0
				else
					out[#out+1] = value.Scale
					out[#out+1] = value.Offset
				end

				return out
			end, 
			-- To Instance
			function(schema, field, value)
				if value == nil then
					return EMPTY_UDIM
				end
				return UDim.new(value[1], value[2])
			end
		},
		-- Array
		{
			-- type
			'double[]',         
			-- default                              
			{},                                             
			-- To Serialize
			function(schema, field, value)    
				local out = {}

				for _, udim in ipairs(value) do
					if typeof(udim) ~= 'UDim' then 
						out[#out+1] = 0
						out[#out+1] = 0
					else
						out[#out+1] = udim.Scale
						out[#out+1] = udim.Offset
					end
				end

				return out
			end, 
			-- To Instance         
			function(schema, field, value)      
				local out = {}
				if value == nil or #value == 0 then 
					return out
				end

				for i = 1, #value, 2 do
					out[#out+1] = UDim.new(value[i], value[i+1])
				end
				return out
			end
		}
	},
	[UDim2] = {
		-- Single
		{
			-- type
			'double[]',
			-- default
			EMPTY_UDIM2,
			-- To Serialize
			function (schema, field, value)
				local out = {}

				if typeof(value) ~= 'UDim2' then 
					out[#out+1] = 0
					out[#out+1] = 0
					out[#out+1] = 0
					out[#out+1] = 0
				else
					out[#out+1] = value.X.Scale
					out[#out+1] = value.X.Offset
					out[#out+1] = value.Y.Scale
					out[#out+1] = value.Y.Offset
				end

				return out
			end, 
			-- To Instance
			function(schema, field, value)
				if value == nil then
					return EMPTY_UDIM2
				end
				return UDim2.new(value[1], value[2], value[3], value[4])
			end
		},
		-- Array
		{
			-- type
			'double[]',         
			-- default                              
			{},                                             
			-- To Serialize
			function(schema, field, value)    
				local out = {}

				for _, udim2 in ipairs(value) do
					if typeof(udim2) ~= 'UDim2' then 
						out[#out+1] = 0
						out[#out+1] = 0
						out[#out+1] = 0
						out[#out+1] = 0
					else
						out[#out+1] = udim2.X.Scale
						out[#out+1] = udim2.X.Offset
						out[#out+1] = udim2.Y.Scale
						out[#out+1] = udim2.Y.Offset
					end
				end

				return out
			end, 
			-- To Instance         
			function(schema, field, value)      
				local out = {}
				if value == nil or #value == 0 then 
					return out
				end

				for i = 1, #value, 4 do
					out[#out+1] = UDim2.new(value[i], value[i+1], value[i+2], value[i+3])
				end
				return out
			end
		}
	},
	[Color3] = {
		-- Single
		{
			-- type
			'double[]',
			-- default
			EMPTY_C3,
			-- To Serialize
			function (schema, field, value)
				local out = {}

				if typeof(value) ~= 'Color3' then 
					out[#out+1] = 0
					out[#out+1] = 0
					out[#out+1] = 0
				else
					out[#out+1] = value.R
					out[#out+1] = value.G
					out[#out+1] = value.B
				end

				return out
			end, 
			-- To Instance
			function(schema, field, value)
				if value == nil then
					return EMPTY_C3
				end
				return Color3.new(value[1], value[2], value[3])
			end
		},
		-- Array
		{
			-- type
			'double[]',         
			-- default                              
			{},                                             
			-- To Serialize
			function(schema, field, value)    
				local out = {}

				for _, c3 in ipairs(value) do
					if typeof(c3) ~= 'Color3' then 
						out[#out+1] = 0
						out[#out+1] = 0
						out[#out+1] = 0
					else
						out[#out+1] = c3.R
						out[#out+1] = c3.G
						out[#out+1] = c3.B
					end
				end

				return out
			end, 
			-- To Instance         
			function(schema, field, value)      
				local out = {}
				if value == nil or #value == 0 then 
					return out
				end

				for i = 1, #value, 3 do
					out[#out+1] = Color3.new(value[i], value[i+1], value[i+2])
				end
				return out
			end
		}
	},
	[ColorSequence] = {
		-- Single
		{
			-- type
			'double[]',
			-- default
			EMPTY_CS,
			-- To Serialize
			function (schema, field, value)
				local out = {}

				if typeof(value) ~= 'ColorSequence' then 
					out[#out+1] = 0
					out[#out+1] = 0
					out[#out+1] = 0
					out[#out+1] = 0
				else
					for _, kp in ipairs(value.Keypoints) do
						out[#out+1] = kp.Time
						out[#out+1] = kp.Value.R
						out[#out+1] = kp.Value.G
						out[#out+1] = kp.Value.B
					end
				end

				return out
			end, 
			-- To Instance
			function(schema, field, value)
				if value == nil then
					return EMPTY_CS
				end
				local keypoints = {}
				for i = 1, #value, 4 do
					table.insert(keypoints, ColorSequenceKeypoint.new(value[i], Color3.new(value[i+1], value[i+2], value[i+3])))
				end
				return ColorSequence.new(keypoints)
			end
		},
		-- Array
		{
			-- type
			'double[]',         
			-- default                              
			{},                                             
			-- To Serialize
			function(schema, field, value)    
				local out = {}

				for _, cs in ipairs(value) do
					if typeof(cs) ~= 'ColorSequence' then 
						out[#out+1] = 0
						out[#out+1] = 0
						out[#out+1] = 0
						out[#out+1] = 0
					else
						for _, kp in ipairs(cs.Keypoints) do
							out[#out+1] = kp.Time
							out[#out+1] = kp.Value.R
							out[#out+1] = kp.Value.G
							out[#out+1] = kp.Value.B
						end
						out[#out+1] = 2 --// Identifier to split between ColorSequences
					end
				end

				return out
			end, 
			-- To Instance         
			function(schema, field, value)      
				local out = {}
				if value == nil or #value == 0 then 
					return out
				end
				
				local cstotal = 0
				for _, val in ipairs(value) do
					if val == 2 then
						cstotal = cstotal + 1
					end
				end
				
				local cvindex = 1
				for _ = 1, cstotal do
					local keypoints = {}
					for i = cvindex, #value, 4 do
						cvindex = cvindex + 1
						if value[i] == 2 then break end
						table.insert(keypoints, ColorSequenceKeypoint.new(value[i], Color3.new(value[i+1], value[i+2], value[i+3])))
					end
					out[#out+1] = ColorSequence.new(keypoints)
				end
				
				return out
			end
		}
	},
	[ColorSequenceKeypoint] = {
		-- Single
		{
			-- type
			'double[]',
			-- default
			EMPTY_CSK,
			-- To Serialize
			function (schema, field, value)
				local out = {}

				if typeof(value) ~= 'ColorSequenceKeypoint' then 
					out[#out+1] = 0
					out[#out+1] = 0
					out[#out+1] = 0
					out[#out+1] = 0
				else
					out[#out+1] = value.Time
					out[#out+1] = value.Value.R
					out[#out+1] = value.Value.G
					out[#out+1] = value.Value.B
				end

				return out
			end, 
			-- To Instance
			function(schema, field, value)
				if value == nil then
					return EMPTY_CSK
				end
				return ColorSequenceKeypoint.new(value[1], Color3.new(value[2], value[3], value[4]))
			end
		},
		-- Array
		{
			-- type
			'double[]',         
			-- default                              
			{},                                             
			-- To Serialize
			function(schema, field, value)    
				local out = {}

				for _, csk in ipairs(value) do
					if typeof(csk) ~= 'ColorSequenceKeypoint' then 
						out[#out+1] = 0
						out[#out+1] = 0
						out[#out+1] = 0
						out[#out+1] = 0
					else
						out[#out+1] = csk.Time
						out[#out+1] = csk.Value.R
						out[#out+1] = csk.Value.G
						out[#out+1] = csk.Value.B
					end
				end

				return out
			end, 
			-- To Instance         
			function(schema, field, value)      
				local out = {}
				if value == nil or #value == 0 then 
					return out
				end

				for i = 1, #value, 4 do
					out[#out+1] = ColorSequenceKeypoint.new(value[i], Color3.new(value[i+1], value[i+2], value[i+3]))
				end

				return out
			end
		}
	}
}

return Converters
