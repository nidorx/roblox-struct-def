local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

local Core = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Core'))
local encode_byte                      = Core.encode_byte
local encode_field                     = Core.encode_field
local FIELD_TYPE_BITMASK_INT53         = Core.FIELD_TYPE_BITMASK_INT53

local Int32 = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Int32'))
local INT6_MAX                      = Int32.INT6_MAX
local INT8_MAX                      = Int32.INT8_MAX
local INT16_MAX                     = Int32.INT16_MAX
local INT24_MAX                     = Int32.INT24_MAX
local INT32_MAX                     = Int32.INT32_MAX
local INT_EXTRA_BITMASK_NEGATIVE    = Int32.INT_EXTRA_BITMASK_NEGATIVE
local INT_EXTRA_BITMASK_BYTE_COUNT  = Int32.INT_EXTRA_BITMASK_BYTE_COUNT
local INT_EXTRA_BITMASK_NUM_BYTES   = Int32.INT_EXTRA_BITMASK_NUM_BYTES

local INT53_MAX                        = 9007199254740991    -- (2^53) -1  [7 bytes]
local INT53_EXTRA_BITMASK_IS_BIG       = 32  -- 00100000
local INT53_EXTRA_BITMASK_HAS_MORE     = 16  -- 00010000
local INT53_EXTRA_BITMASK_BYTE_COUNT   = 3   -- 00000011

-- how many bytes [chars] is used by the rest of int53 in the sequence (4 values)
local INT53_EXTRA_BITMASK_NUM_BYTES = {
   0, -- 00000000   = 1 byte
   1, -- 00000001   = 2 bytes
   2, -- 00000010   = 3 bytes
   3  -- 00000011   = 4 bytes
}

--[[
   Logic common to the encode_int53 and encode_int53_array methods

   Does it encode an int53, in the format <{EXTRA} [{VALUE}]?>

   {EXTRA}
      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | +-+--- 2 bits  how many bytes [chars] is used by the rest of int32 (4 values)
      | | | | +-+------- 2 bits  how many bytes [chars] is used by the multiplier int32 (4 values)
      | | | +----------- 1 bits  HAS_MORE? Used by encode_int53_array to indicate continuity
      | | +------------- 1 bits  Number is greater than 32 bits, if positive it was broken in teams and rest
      | +--------------- 1 bit   discarded
      +----------------- 1 bit   0 = POSITIVE, 1 = NEGATIVE

   [{VALUE}]
      Up to 7 bytes of the number being serialized

   @header     {Object} Header reference
   @out        {array}  The output being generated
   @value      {int32}  Value that will be serialized
   @hasMore    {bool}   Used by encode_int53_array to indicate continuity
]]
local function encode_int53_out(header, out, value, hasMore)
   local byteExtra = 0
   if value < 0 then 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NEGATIVE)
   end
   
   if hasMore then 
      byteExtra = bor(byteExtra, INT53_EXTRA_BITMASK_HAS_MORE)
   end

   -- normalizes the number to the limit of int43
   value = math.min(INT53_MAX, math.max(0, math.abs(value)))

   if value <= INT8_MAX then
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

   elseif value <= INT32_MAX then
      -- (2^32) -1  [4 bytes] = "11111111 11111111 11111111 11111111"

      -- 4 bytes 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[4])
      out[#out + 1] = encode_byte(header, byteExtra)

      -- 4 bytes
      out[#out + 1] = encode_byte(header, band(rshift(value, 24), 0xFF))
      out[#out + 1] = encode_byte(header, band(rshift(value, 16), 0xFF))
      out[#out + 1] = encode_byte(header, band(rshift(value, 8), 0xFF))
      out[#out + 1] = encode_byte(header, band(value, 0xFF))

   else
      -- number greater than 32 bits, it is not possible to manipulate using the bit32 lib, it is necessary to 
      -- break the number so it fits in up to 7 bytes

      -- number is big
      byteExtra = bor(byteExtra, INT53_EXTRA_BITMASK_IS_BIG)

      local times = math.floor(value/INT32_MAX)-1
      local rest = value - (times+1)*INT32_MAX

      local bytes = {}

      -- number of bytes used by the multiplier (up to 3)
      if times <= INT8_MAX then
         bytes[#bytes + 1] = times

      elseif times <= INT16_MAX then
         byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[2])         
         bytes[#bytes + 1] = band(rshift(times, 8), 0xFF)
         bytes[#bytes + 1] = band(times, 0xFF)
         
      else
         byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[3])         
         bytes[#bytes + 1] = band(rshift(times, 16), 0xFF)
         bytes[#bytes + 1] = band(rshift(times, 8), 0xFF)
         bytes[#bytes + 1] = band(times, 0xFF)
      end 

      -- number of bytes used by the rest, up to 4
      if rest <= INT8_MAX then
         bytes[#bytes + 1] = rest

      elseif rest <= INT16_MAX then
         byteExtra = bor(byteExtra, INT53_EXTRA_BITMASK_NUM_BYTES[2])
         bytes[#bytes + 1] = band(rshift(rest, 8), 0xFF)
         bytes[#bytes + 1] = band(rest, 0xFF)

      elseif rest <= INT24_MAX then
         byteExtra = bor(byteExtra, INT53_EXTRA_BITMASK_NUM_BYTES[3])
         bytes[#bytes + 1] = band(rshift(rest, 16), 0xFF)
         bytes[#bytes + 1] = band(rshift(rest, 8), 0xFF)
         bytes[#bytes + 1] = band(rest, 0xFF)

      else
         byteExtra = bor(byteExtra, INT53_EXTRA_BITMASK_NUM_BYTES[4])   
         bytes[#bytes + 1] = band(rshift(rest, 24), 0xFF)
         bytes[#bytes + 1] = band(rshift(rest, 16), 0xFF)
         bytes[#bytes + 1] = band(rshift(rest, 8), 0xFF)
         bytes[#bytes + 1] = band(rest, 0xFF)

      end

      -- EXTRA
      out[#out + 1] = encode_byte(header, byteExtra)

      -- [<VALUE>]
      for _, byte in ipairs(bytes) do
         out[#out + 1] = encode_byte(header, byte)
      end
   end
end

--[[
   Does the encode of an int53, in the format <{EXTRA}[{VALUE}]?>, See `encode_int53_out(header, out, value)`

   @header     {Object} Header reference
   @field      {Object} The reference for the field
   @value      {int32}  Value that will be serialized
]]
local function encode_int53(header, field, value)

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
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_INT53, false)
   }

   encode_int53_out(header, out, value, false)

   return table.concat(out, '')
end

--[[
   Decode the EXTRA of an int 53, see `encode_int53(header, fieldId, value)`

   @byteExtra  {byte} The EXTRA byte that was generated by the `encode_int53 (header, fieldId, value)` method

   @return {Object} information contained in EXTRA
]]
local function decode_int53_extra_byte(byteExtra)
  
   local out = {}
   out.IsNegative  = band(byteExtra, INT_EXTRA_BITMASK_NEGATIVE) ~= 0
   out.IsBig       = band(byteExtra, INT53_EXTRA_BITMASK_IS_BIG)  ~= 0
   out.HasMore     = band(byteExtra, INT53_EXTRA_BITMASK_HAS_MORE) ~= 0
   out.BytesTimes  = rshift(band(byteExtra, INT_EXTRA_BITMASK_BYTE_COUNT), 2) + 1
   out.BytesRest   = band(byteExtra, INT53_EXTRA_BITMASK_BYTE_COUNT) + 1

   return out
end

--[[
   Decodes the bytes that make up an int53, only when it is BIG, see function `encode_int53(header, fieldId, value)`

   @bytes      {byte[]} The bytes that were generated by the `encode_int53(header, fieldId, value)` method
   @isNegative {bool}   The value is negative (information is in the EXTRA byte)
   @timesLen   {number} How many bytes is part of the x32 multiplier
   @restLen    {number} How many bytes is part of the rest

   @return {int53}
]]
local function decode_int53_bytes(bytes, isNegative, timesBytes, restBytes)
   local times, rest, value

   if timesBytes == 1 then
      times = bytes[1]
   elseif timesBytes == 2 then
      times = bor(lshift(bytes[1], 8), bytes[2])
   else
      times = bor(lshift(bytes[1], 16), bor(lshift(bytes[2], 8), bytes[3]))
   end

   if restBytes == 1 then
      rest =  bytes[timesBytes + 1]

   elseif restBytes == 2 then
      rest =  bor(lshift(bytes[timesBytes + 1], 8), bytes[timesBytes + 2])

   elseif restBytes == 3 then
      rest =  bor(lshift(bytes[timesBytes + 1], 16), bor(lshift(bytes[timesBytes + 2], 8), bytes[timesBytes + 3]))

   else
      rest =  bor(lshift(bytes[timesBytes + 1], 24), bor(lshift(bytes[timesBytes + 2], 16), bor(lshift(bytes[timesBytes + 3], 8), bytes[timesBytes + 4])))
   end

   value = (times+1) * INT32_MAX + rest

   if isNegative then 
      value = -1 * value
   end

   return value
end

--[[
   Encodes an int53 [], in the format [<{EXTRA} [{VALUE}]>], repeating the pattern until all numbers are serialized

   See `encode_int53(header, fieldId, value)`

   @header     {Object}    Header reference
   @field      {Object}    The reference for the field
   @values     {int53[]}   The values that will be serialized
]]
local function encode_int53_array(header, field, values)
   if values == nil or #values == 0 then
      -- ignore
      return '' 
   end
   
   local out = {
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_INT53, true)
   }
   
   local byteExtra   = 0

   local len   = #values
   for i, value in ipairs(values) do
      if value == nil or type(value) ~= 'number' then
         -- invalid, ignore
         value = 0
      end
   
      -- rounds the number, if double
      value = math.round(value)

      encode_int53_out(header, out, value, i ~= len)
   end

   return table.concat(out, '')
end

local Int53 = {}
Int53.encode_int53              = encode_int53
Int53.decode_int53_extra_byte   = decode_int53_extra_byte
Int53.decode_int53_bytes        = decode_int53_bytes
Int53.encode_int53_array        = encode_int53_array
Int53.INT53_MAX                 = INT53_MAX
return Int53
