--[[
   Os conversores para os tipos padrões do Roblox https://developer.roblox.com/en-us/api-reference/data-types
]]

local EMPTY_VEC3 = Vector3.new(0, 0, 0)

local Conversors = {
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
   }
}


return Conversors
