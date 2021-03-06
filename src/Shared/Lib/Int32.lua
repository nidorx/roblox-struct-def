local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

local Core = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Core'))
local encode_byte                      = Core.encode_byte
local encode_field                     = Core.encode_field
local FIELD_TYPE_BITMASK_INT32         = Core.FIELD_TYPE_BITMASK_INT32

local INT_EXTRA_BITMASK_NEGATIVE       = 128 -- 10000000
local INT_EXTRA_BITMASK_IT_FITS        = 64  -- 01000000
local INT_EXTRA_BITMASK_VALUE          = 63  -- 00111111
local INT_EXTRA_BITMASK_BYTE_COUNT     = 12  -- 00001100

-- how many bytes [chars] is used by int32 in the sequence (4 values)
-- Used by int53 to determine the multiplier
local INT_EXTRA_BITMASK_NUM_BYTES = {
   0,    -- 00000000   = 1 byte
   4,    -- 00000100   = 2 bytes
   8,    -- 00001000   = 3 bytes
   12    -- 00001100   = 4 bytes
}

-- https://en.wikipedia.org/wiki/Integer_(computer_science)
local INT6_MAX   = 63                 --   (2^6) -1   [6 bits]
local INT8_MAX   = 255                 --  (2^8) -1   [1 byte]
local INT16_MAX  = 65535               -- (2^16) -1  [2 bytes]
local INT24_MAX  = 16777215            -- (2^24) -1  [3 bytes]
local INT32_MAX  = 4294967295          -- (2^32) -1  [4 bytes]

--[[
   Does it encode an int32, in the format <{EXTRA}[{VALUE}]?>

   {EXTRA}
      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | +-+--- 2 bits  discarded if number greater than 63
      | | | | +-+------- 2 bits  how many bytes [chars] is used by int32 in the sequence (4 values)
      | | +-+----------- 2 bits  discarded if number greater than 63
      | +--------------- 1 bit   number fits in the next bits? If number is <= 63 (2 ^ 6) -1 its content is already 
      |                             formed by the next bits. If not, validates next 2 bits
      +----------------- 1 bit   0 = POSITIVE, 1 = NEGATIVE

   [{VALUE}]
      Up to 4 bytes of the number being serialized
      When number is <= 63 (2 ^ 6) -1 the value is already serialized in EXTRA

   @header     {Object} Header reference
   @field      {Object} The reference for the field
   @value      {int32}  Value that will be serialized
]]
local function encode_int32(header, field, value)

   if value == nil or type(value) ~= 'number' then
      -- invalid, ignore
      return '' 
   end

   -- rounds the number, if double
   value = math.round(value)
   if value == 0 then
      -- ignore
      return '' 
   end

   local out = {
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_INT32, false)
   }

   local byteExtra = 0
   if value < 0 then 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NEGATIVE)
   end

   -- normalizes the number to the limit of int32
   value = math.min(INT32_MAX, math.max(0, math.abs(value)))

   if value <= INT6_MAX then
      -- number fits in the next bits

      byteExtra = bor(byteExtra, value)
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_IT_FITS)
      
      out[#out + 1] = encode_byte(header, byteExtra)

   elseif value <= INT8_MAX then
      -- (2^8) -1  [1 byte] = "11111111"

      -- 1 byte 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[1])
      out[#out + 1] = encode_byte(header, byteExtra)

      -- 1 byte
      out[#out + 1] = encode_byte(header, value)
   
   elseif value <= INT16_MAX then
      -- (2^16) -1  [2 bytes] = "11111111 11111111"

      -- 2 bytes 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[2])
      out[#out + 1] = encode_byte(header, byteExtra)

      -- 2 bytes
      out[#out + 1] = encode_byte(header, band(rshift(value, 8), 0xFF))
      out[#out + 1] = encode_byte(header, band(value, 0xFF))

   elseif value <= INT24_MAX then
      -- (2^24) -1  [3 bytes] = "11111111 11111111 11111111"

      -- 3 bytes 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[3])
      out[#out + 1] = encode_byte(header, byteExtra)

      -- 3 bytes
      out[#out + 1] = encode_byte(header, band(rshift(value, 16), 0xFF))
      out[#out + 1] = encode_byte(header, band(rshift(value, 8), 0xFF))
      out[#out + 1] = encode_byte(header, band(value, 0xFF))

   else
      -- (2^32) -1  [4 bytes] = "11111111 11111111 11111111 11111111"

      -- 3 bytes 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[4])
      out[#out + 1] = encode_byte(header, byteExtra)

      -- 4 bytes
      out[#out + 1] = encode_byte(header, band(rshift(value, 24), 0xFF))
      out[#out + 1] = encode_byte(header, band(rshift(value, 16), 0xFF))
      out[#out + 1] = encode_byte(header, band(rshift(value, 8), 0xFF))
      out[#out + 1] = encode_byte(header, band(value, 0xFF))
   end

   return table.concat(out, '')
end

--[[
   Decode the EXTRA of an int32, see `encode_int32(header, fieldId, value)`

   @byteExtra  {byte} The EXTRA byte that was generated by the `encode_int32(header, fieldId, value)` method

   @return {Object} information contained in EXTRA
]]
local function decode_int32_extra_byte(byteExtra)
   local out = {}   
   local isNegative = band(byteExtra, INT_EXTRA_BITMASK_NEGATIVE) ~= 0

   if band(byteExtra, INT_EXTRA_BITMASK_IT_FITS) ~= 0 then 
      -- value fits in the last 6 bits
      local value = band(byteExtra, INT_EXTRA_BITMASK_VALUE)
      if isNegative then 
         value = -1 * value
      end
     
      out.ValueFits   = true
      out.Value       = value
      
   else 
      out.Bytes       = rshift(band(byteExtra, INT_EXTRA_BITMASK_BYTE_COUNT), 2) + 1
      out.ValueFits   = false
      out.IsNegative  = isNegative
   end

   return out
end

--[[
   Decodes the bytes that make up an int32, see function `encode_int32(header, fieldId, value)`

   @bytes      {byte[]} The bytes that were generated by the `encode_int32(header, fieldId, value)` method
   @isNegative {bool}   The value is negative (information is in the EXTRA byte)

   @return {int32}

]]
local function decode_int32_bytes(bytes, isNegative)
   local len = #bytes
   local value
   if len == 1 then
      value =  bytes[1]

   elseif len == 2 then
      value =  bor(lshift(bytes[1], 8), bytes[2])

   elseif len == 3 then
      value =  bor(lshift(bytes[1], 16), bor(lshift(bytes[2], 8), bytes[3]))

   else
      value =  bor(lshift(bytes[1], 24), bor(lshift(bytes[2], 16), bor(lshift(bytes[3], 8), bytes[4])))
   end

   if isNegative then 
      value = -1 * value
   end

   return value
end


local INT32_ARRAY_EXTRA_BITMASK_NEGATIVE = {
   32,   -- 00100000 - FIRST
   2,    -- 00000010 - SECOND
}

local INT32_ARRAY_EXTRA_BITMASK_HAS_MORE = {
   16,   -- 00010000 - FIRST
   1,    -- 00000001 - SECOND
}

-- MASK & SHIFT
local INT32_ARRAY_EXTRA_BITMASK_BYTE_COUNT = {
   {192, 6},  -- 11000000
   {12, 2},   -- 00001100
}

-- how many bytes [chars] is used by int32 in the sequence (4 values)
local INT32_ARRAY_EXTRA_BITMASK_NUM_BYTES = {
   -- FIRST
   {
      0,    -- 00000000   = 1 byte
      64,   -- 01000000   = 2 bytes
      128,  -- 10000000   = 3 bytes
      192   -- 11000000   = 4 bytes
   },
   -- SECOND
   {
      0,    -- 00000000   = 1 byte
      4,    -- 00000100   = 2 bytes
      8,    -- 00001000   = 3 bytes
      12    -- 00001100   = 4 bytes
   }
}

--[[
   Encodes an int32 [], in the format [<{EXTRA}[{VALUE}]>], repeating the pattern until all numbers are serialized

   {EXTRA}
      There is 1 extra for every two numbers

      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | | +--- 1 bit   HAVE MORE? If so, the next byte is also part of the array, the same structure
      | | | | | | +----- 1 bit   2nd int32 in sequence: is 0 = POSITIVE, 1 = NEGATIVE
      | | | | +-+------- 2 bits  2nd int32 in sequence: how many bytes [chars] is used
      | | | +----------- 1 bit   HAVE MORE?
      | | +------------- 1 bit   1st int32 in sequence: is 0 = POSITIVE, 1 = NEGATIVE
      +-+--------------- 2 bits  1st int32 in sequence: how many bytes [chars] is used

   [{VALUE}]
      Up to 4 bytes per number being serialized

   @header     {Object}    Header reference
   @field      {Object}    The reference for the field
   @values     {int32[]}   The values that will be serialized
]]
local function encode_int32_array(header, field, values)
   if values == nil or #values == 0 then
      -- ignore
      return '' 
   end
   
   local out = {
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_INT32, true)
   }
   
   local byteExtra   = 0
   local bytes       = {}

   local len   = #values
   local index = 1
   for i, value in ipairs(values) do
      if value == nil or type(value) ~= 'number' then
         value = 0 
      end
   
      -- rounds the number, if double
      value = math.round(value)
   
      if value < 0 then
         byteExtra = bor(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NEGATIVE[index])
      end

      -- HAS MORE
      if i < len then 
         byteExtra = bor(byteExtra, INT32_ARRAY_EXTRA_BITMASK_HAS_MORE[index])
      end
   
      -- normalizes the number to the limit of int32
      value = math.min(INT32_MAX, math.max(0, math.abs(value)))
   
      if value <= INT8_MAX then
         -- (2^8) -1  [1 byte] = "11111111"
   
         -- 1 byte
         bytes[#bytes + 1] = value
      
      elseif value <= INT16_MAX then
         -- (2^16) -1  [2 bytes] = "11111111 11111111"
   
         -- 2 bytes 
         byteExtra = bor(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NUM_BYTES[index][2])
   
         -- 2 bytes
         bytes[#bytes + 1] = band(rshift(value, 8), 0xFF)
         bytes[#bytes + 1] = band(value, 0xFF)
   
      elseif value <= INT24_MAX then
         -- (2^24) -1  [3 bytes] = "11111111 11111111 11111111"
   
         -- 3 bytes 
         byteExtra = bor(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NUM_BYTES[index][3])
   
         -- 3 bytes
         bytes[#bytes + 1] = band(rshift(value, 16), 0xFF)
         bytes[#bytes + 1] = band(rshift(value, 8), 0xFF)
         bytes[#bytes + 1] = band(value, 0xFF)
   
      else
         -- (2^32) -1  [4 bytes] = "11111111 11111111 11111111 11111111"
   
         -- 4 bytes 
         byteExtra = bor(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NUM_BYTES[index][4])
   
         -- 4 bytes
         bytes[#bytes + 1] = band(rshift(value, 24), 0xFF)
         bytes[#bytes + 1] = band(rshift(value, 16), 0xFF)
         bytes[#bytes + 1] = band(rshift(value, 8), 0xFF)
         bytes[#bytes + 1] = band(value, 0xFF)
      end


      index = index + 1

      if index > 2 then
         -- EXTRA
         out[#out + 1] = encode_byte(header, byteExtra)

         -- [<VALUE>]
         for _, byte in ipairs(bytes) do
            out[#out + 1] = encode_byte(header, byte)
         end

         -- reset
         index       = 1
         byteExtra   = 0
         bytes       = {}
      end
   end

   -- residual
   if index > 1 then
      -- EXTRA
      out[#out + 1] = encode_byte(header, byteExtra)

      -- [<VALUE>]
      for _, byte in ipairs(bytes) do
         out[#out + 1] = encode_byte(header, byte)
      end
   end

   return table.concat(out, '')
end

--[[
   Decode the EXTRA of an int32, see `encode_int32_array(header, fieldId, value)`

   @byteExtra  {byte} The EXTRA byte that was generated by the `encode_int32_array(header, fieldId, value)` method

   @return {Object} information contained in EXTRA
]]
local function   decode_int32_array_extra_byte(byteExtra)

   local out = {}

   local entry = {}
   entry.Bytes       = rshift(band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_BYTE_COUNT[1][1]), INT32_ARRAY_EXTRA_BITMASK_BYTE_COUNT[1][2]) + 1
   entry.IsNegative  = band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NEGATIVE[1]) ~= 0
   entry.HasMore     = band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_HAS_MORE[1]) ~= 0

   out.Items  = {entry}
  
   -- has more
   if out.Items[1].HasMore then 
      local entry = {}
      entry.Bytes       = rshift(band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_BYTE_COUNT[2][1]), INT32_ARRAY_EXTRA_BITMASK_BYTE_COUNT[2][2]) + 1
      entry.IsNegative  = band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NEGATIVE[2]) ~= 0
      entry.HasMore     = band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_HAS_MORE[2]) ~= 0
      table.insert(out.Items, entry)
   end

   return out
end


local Int32 = {}
Int32.encode_int32                  = encode_int32
Int32.decode_int32_extra_byte       = decode_int32_extra_byte
Int32.decode_int32_bytes            = decode_int32_bytes
Int32.encode_int32_array            = encode_int32_array
Int32.decode_int32_array_extra_byte = decode_int32_array_extra_byte
Int32.INT6_MAX                      = INT6_MAX
Int32.INT8_MAX                      = INT8_MAX
Int32.INT16_MAX                     = INT16_MAX
Int32.INT24_MAX                     = INT24_MAX
Int32.INT32_MAX                     = INT32_MAX
Int32.INT_EXTRA_BITMASK_NEGATIVE    = INT_EXTRA_BITMASK_NEGATIVE
Int32.INT_EXTRA_BITMASK_IT_FITS     = INT_EXTRA_BITMASK_IT_FITS
Int32.INT_EXTRA_BITMASK_VALUE       = INT_EXTRA_BITMASK_VALUE
Int32.INT_EXTRA_BITMASK_BYTE_COUNT  = INT_EXTRA_BITMASK_BYTE_COUNT
Int32.INT_EXTRA_BITMASK_NUM_BYTES   = INT_EXTRA_BITMASK_NUM_BYTES
return Int32
