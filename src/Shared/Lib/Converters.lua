--[[
   Converters for standard Roblox types 
   https://developer.roblox.com/en-us/api-reference/data-types
]]

local EMPTY_VEC2 = Vecto2.new(0, 0)
local EMPTY_VEC3 = Vector3.new(0, 0, 0)
local EMPTY_CFRAME = CFrame.new()
local EMPTY_COLOR3 = Color3.new(1, 1, 1)

local Converters = {
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
               if typeof(vec3) ~= 'Vector2' then 
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
   [CFrame] = {
      -- Single
      {
         -- type
         'double[]',
         -- default
         EMPTY_CFRAME,
         -- To Serialize
         function (schema, field, value)
            local out = {}
         
            if typeof(value) ~= 'CFrame' then 
               -- Position
               out[#out+1] = 0
               out[#out+1] = 0
               out[#out+1] = 0
               -- Right Vector
               out[#out+1] = 0
               out[#out+1] = 0
               out[#out+1] = 0
               -- Up Vector
               out[#out+1] = 0
               out[#out+1] = 0
               out[#out+1] = 0
               -- Look Vector
               out[#out+1] = 0
               out[#out+1] = 0
               out[#out+1] = 0
            else
               -- Position
               out[#out+1] = value.X
               out[#out+1] = value.Y
               out[#out+1] = value.Z
               -- Right Vector
               out[#out+1] = value.RightVector.X
               out[#out+1] = value.RightVector.Y
               out[#out+1] = value.RightVector.Z
               -- Up Vector
               out[#out+1] = value.UpVector.X
               out[#out+1] = value.UpVector.Y
               out[#out+1] = value.UpVector.Z
               -- Look Vector
               out[#out+1] = value.LookVector.X
               out[#out+1] = value.LookVector.Y
               out[#out+1] = value.LookVector.Z

            end
         
            return out
         end, 
         -- To Instance
         function(schema, field, value)
            if value == nil then
               return EMPTY_CFRAME
            end
            return CFrame.new(value[1], value[2], value[3],
                              value[4], value[5], value[6],
                              value[7], value[8], value[9],
                              value[10], value[11], value[12])
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
         
            for _, cframe in ipairs(value) do
               if typeof(cframe) ~= 'Vector3' then 
                  -- Position
                  out[#out+1] = 0
                  out[#out+1] = 0
                  out[#out+1] = 0
                  -- Right Vector
                  out[#out+1] = 0
                  out[#out+1] = 0
                  out[#out+1] = 0
                  -- Up Vector
                  out[#out+1] = 0
                  out[#out+1] = 0
                  out[#out+1] = 0
                  -- Look Vector
                  out[#out+1] = 0
                  out[#out+1] = 0
                  out[#out+1] = 0
               else
                  -- Position
                  out[#out+1] = cframe.X
                  out[#out+1] = cframe.Y
                  out[#out+1] = cframe.Z
                  -- Right Vector
                  out[#out+1] = cframe.RightVector.X
                  out[#out+1] = cframe.RightVector.Y
                  out[#out+1] = cframe.RightVector.Z
                  -- Up Vector
                  out[#out+1] = cframe.UpVector.X
                  out[#out+1] = cframe.UpVector.Y
                  out[#out+1] = cframe.UpVector.Z
                  -- Look Vector
                  out[#out+1] = cframe.LookVector.X
                  out[#out+1] = cframe.LookVector.Y
                  out[#out+1] = cframe.LookVector.Z
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
      
            for i = 1, #value, 12 do
               out[#out+1] = CFrame.new(value[i], value[i+1], value[i+2],
                                       value[i+3], value[i+4], value[i+5],
                                       value[i+6], value[i+7], value[i+8],
                                       value[i+9], value[i+10], value[i+11])
            end
            return out
         end
      }
   },
   [Color3] = {
      -- Single
      {
         -- type
         'int32[]',
         -- default
         EMPTY_COLOR3,
         -- To Serialize
         function (schema, field, value)
            local out = {}
         
            if typeof(value) ~= 'Color3' then 
               out[#out+1] = 255
               out[#out+1] = 255
               out[#out+1] = 255
            else
               out[#out+1] = math.floor(value.R * 255)
               out[#out+1] = math.floor(value.G * 255)
               out[#out+1] = math.floor(value.B * 255)
            end
         
            return out
         end, 
         -- To Instance
         function(schema, field, value)
            if value == nil then
               return EMPTY_COLOR33
            end
            return Color3.fromRGB(value[1], value[2], value[3])
         end
      },
      -- Array
      {
         -- type
         'int32[]',
         -- default
         {},
         -- To Serialize
         function(schema, field, value)    
            local out = {}
         
            for _, col3 in ipairs(value) do
               if typeof(col3) ~= 'Color3' then 
                  out[#out+1] = 255
                  out[#out+1] = 255
                  out[#out+1] = 255
               else
                  out[#out+1] = math.floor(col3.R)
                  out[#out+1] = math.floor(col3.G)
                  out[#out+1] = math.floor(col3.B)
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
               out[#out+1] = Color3.fromRGB(value[i], value[i+1], value[i+2])
            end
            return out
         end
      }
   }
}


return Converters
