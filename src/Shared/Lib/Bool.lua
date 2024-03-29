local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

local Core = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Core'))
local encode_byte                      = Core.encode_byte
local encode_field                     = Core.encode_field
local FIELD_TYPE_BITMASK_BOOL          = Core.FIELD_TYPE_BITMASK_BOOL
local FIELD_TYPE_BITMASK_BOOL_ARRAY    = Core.FIELD_TYPE_BITMASK_BOOL_ARRAY


local BOOL_ARRAY_BITMASK_COUNT      = 192 -- 11000000
local BOOL_ARRAY_BITMASK_VALUES     = 16  -- 00111100
local BOOL_ARRAY_BITMASK_HAS_MORE   = 1   -- 00000001

-- The mask to determine how many booleans there are in this byte
local BOOL_ARRAY_BITMASK_COUNT_VALUES = {
   0,    -- 00000000 = 1 bool
   64,   -- 01000000 = 2 bool
   128,  -- 10000000 = 3 bool
   192   -- 11000000 = 4 bool
}

-- The value mask for the bool array
local BOOL_ARRAY_BITMASK_VALUE = {
   32, -- 000100000
   16, -- 000010000
   8,  -- 000001000
   4   -- 000000100
}

--[[
   when bool, use the IS_ARRAY bit to save the value

   1 1 1 1 1 1 1 1
   |   | | |     |
   |   | | +-----+--- 4 bits  FIELD_ID
   |   | |            
   |   | +----------- 1 bit   IS_ARRAY -> FIELD_TYPE_BITMASK_BOOL (TRUE ou FALSE)
   +---+------------- 3 bits  FIELD_TYPE

   @header     {Object} Reference to the header
   @field      {Object} The reference for the field
   @value      {bool}   Value being serialized
]]
local function encode_bool(header, field, value)
   return encode_field(header, field.Id, FIELD_TYPE_BITMASK_BOOL, value == true)
end

--[[
   An array of Booleans is encoded in the following format

   [<VALUE>]

   1 1 1 1 1 1 1 1
   | | |     | | |
   | | |     | | +--- 1 bit   HAS_MORE? If so, the next byte is also part of the array, the same structure
   | | |     | | 
   | | |     | +----- 1 bit   discarded
   | | |     | 
   | | +-----+------- 4 bits  that can be part of the array
   | |
   +-+--------------- 2 bit   determines how many next bits are part of the array (up to 4 values)

   @header     {Object} Reference to the header
   @field      {Object} The reference for the field
   @value      {bool[]} Values being serialized
]]
local function encode_bool_array(header, field, value)

   local len = table.getn(value)
   if value == nil or len == 0 then
      -- listas vazias são ignoradas
      return '' 
   end

   local out      = {}
   local index    = 0
   local byte     = 0

   for i, val in ipairs(value) do
      index = index + 1
      
      if index > 4 then
         -- count
         byte = bor(byte, BOOL_ARRAY_BITMASK_COUNT_VALUES[4])
      
         if i < len then
            -- TEM MAIS
            byte = bor(byte, 1)
         end
         
         if #out == 0 then
            -- only does header encode if there is data
            out[#out + 1] = encode_field(header, field.Id, FIELD_TYPE_BITMASK_BOOL_ARRAY, true)
         end

         out[#out + 1] = encode_byte(header, byte)

         -- reset
         byte  = 0
         index = 1
      end

      if val then
         -- 0001 | 00010 = 0011
         byte = bor(byte, BOOL_ARRAY_BITMASK_VALUE[index])
      end
   end

   -- Are there any residual items?
   if index > 0 then
      -- count
      byte = bor(byte, BOOL_ARRAY_BITMASK_COUNT_VALUES[index])

      if #out == 0 then
         -- only does header encode if there is data
         out[#out + 1] = encode_field(header, field.Id, FIELD_TYPE_BITMASK_BOOL_ARRAY, true)
      end

      out[#out + 1]  = encode_byte(header, byte)
   end

   return table.concat(out, '')
end

--[[
   Decodes a byte encoded by the `encode_bool_array(header, fieldId, value)` method

   @byte    {byte}         The byte that was generated by the `encode_bool_array(header, fieldId, value)` method
   @array   {Array<bool>}  The array that will receive the processed data

   @return {bool} True if you have more items to be processed in the sequence
]]
local function decode_bool_array_byte(byte, array)
   local count = rshift(band(byte, BOOL_ARRAY_BITMASK_COUNT), 6) + 1

   for index = 1, count do
      table.insert(array, band(byte, BOOL_ARRAY_BITMASK_VALUE[index]) > 0)
   end

   -- has more
   return band(byte, BOOL_ARRAY_BITMASK_HAS_MORE) > 0
end



local Bool = {}
Bool.encode_bool              = encode_bool
Bool.encode_bool_array        = encode_bool_array
Bool.decode_bool_array_byte   = decode_bool_array_byte
return Bool
