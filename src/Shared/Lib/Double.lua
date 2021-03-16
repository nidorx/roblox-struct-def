local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

local Core = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Core'))
local encode_byte                      = Core.encode_byte
local encode_field                     = Core.encode_field
local FIELD_TYPE_BITMASK_DOUBLE         = Core.FIELD_TYPE_BITMASK_DOUBLE

local Int32 = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Int32'))
local INT6_MAX                      = Int32.INT6_MAX
local INT8_MAX                      = Int32.INT8_MAX
local INT16_MAX                     = Int32.INT16_MAX
local INT24_MAX                     = Int32.INT24_MAX
local INT32_MAX                     = Int32.INT32_MAX
local INT_EXTRA_BITMASK_NEGATIVE    = Int32.INT_EXTRA_BITMASK_NEGATIVE
local INT_EXTRA_BITMASK_BYTE_COUNT  = Int32.INT_EXTRA_BITMASK_BYTE_COUNT
local INT_EXTRA_BITMASK_NUM_BYTES   = Int32.INT_EXTRA_BITMASK_NUM_BYTES

local Int53 = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Int53'))
local INT53_MAX   = Int53.INT53_MAX

local DBL_EXTRA_BITMASK_INT_MULT_M  = 96  -- 01100000
local DBL_EXTRA_BITMASK_INT_REST_M  = 24  -- 00011000
local DBL_EXTRA_BITMASK_HAS_DEC     = 4   -- 00000100
local DBL_EXTRA_BITMASK_DEC_BYTES   = 2   -- 00000010
local DBL_EXTRA_BITMASK_HAS_MORE    = 1   -- 00000001

-- how many bytes [chars] is used by the rest of int32 (4 values)
local DBL_EXTRA_BITMASK_INT_REST = {
   0,    -- 00000000   = 1 byte
   8,    -- 00001000   = 2 bytes
   16,   -- 00010000   = 3 bytes
   24    -- 00011000   = 4 bytes
}

local DBL_EXTRA_BITMASK_INT_MULT = {
   0,    -- 00000000   = 0 byte
   32,   -- 00100000   = 1 bytes
   64,   -- 01000000   = 2 bytes
   96    -- 01100000   = 3 bytes
}

--[[
   Logic common to the encode_double and encode_double_array methods

   Does it encode a double, in the format <{EXTRA} [{VALUE}]?>

   {EXTRA}
      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | | |
      | | | | | | | +--- 1 bits  HAS_MORE? Used by encode_double_array to indicate continuity
      | | | | | | +----- 1 bit   how many bytes [chars] is used by the decimals (2 values)
      | | | | | +------- 1 bit   Number has decimals
      | | | +-+--------- 2 bits  how many bytes [chars] is used by the rest of int32 (4 values)
      | +-+------------- 2 bits  how many bytes [chars] is used by the multiplier int32 (4 values), when BIG
      +----------------- 1 bit   0 = POSITIVE, 1 = NEGATIVE

   [{VALUE}]
      Up to 8 bytes of the number being serialized, being
         - up to 2 bytes for the entire part multiplier
         - up to 4 bytes for the rest of the entire part
         - up to 2 bytes for decimals

   @header     {Object} Header reference
   @out        {array}  The output being generated
   @value      {int32}  Value that will be serialized
   @hasMore    {bool}   When array, allows to define if there are more numbers in the sequence
]]
local function encode_double_out(header, out, value, hasMore)

   local byteExtra = 0
   if value < 0 then 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NEGATIVE)
   end
   
   if hasMore then 
      byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_HAS_MORE)
   end

   local hasDecimal = false

   value       = math.abs(value)
   local int53 = math.floor(value)
   local dec   = math.floor((value - int53) * 10000)
   
   if int53 ~= value then
      hasDecimal = true 
   end
   
   -- normalizes the number to the limit of int53
   int53 = math.min(INT53_MAX, math.max(0, int53))

   local bytes = {}

   if int53 <= INT8_MAX then
      -- (2^8) -1  [1 byte] = "11111111"

      -- 1 byte
      bytes[#bytes + 1] = int53
   
   elseif int53 <= INT16_MAX then
      -- (2^16) -1  [2 bytes] = "11111111 11111111"

      -- 2 bytes 
      byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_REST[2])

      -- 2 bytes
      bytes[#bytes + 1] = band(rshift(int53, 8), 0xFF)
      bytes[#bytes + 1] = band(int53, 0xFF)

   elseif int53 <= INT24_MAX then
      -- (2^24) -1  [3 bytes] = "11111111 11111111 11111111"

      -- usa 3 bytes 
      byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_REST[3])

      -- 3 bytes
      bytes[#bytes + 1] = band(rshift(int53, 16), 0xFF)
      bytes[#bytes + 1] = band(rshift(int53, 8), 0xFF)
      bytes[#bytes + 1] = band(int53, 0xFF)

   elseif int53 <= INT32_MAX then
      -- (2^32) -1  [4 bytes] = "11111111 11111111 11111111 11111111"

      -- usa 4 bytes 
      byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_REST[4])

      -- 4 bytes
      bytes[#bytes + 1] = band(rshift(int53, 24), 0xFF)
      bytes[#bytes + 1] = band(rshift(int53, 16), 0xFF)
      bytes[#bytes + 1] = band(rshift(int53, 8), 0xFF)
      bytes[#bytes + 1] = band(int53, 0xFF)

   else
      -- number greater than 32 bits, it is not possible to manipulate using the bit32 lib, it is necessary to 
      -- break the number so it fits in up to 7 bytes

      local times = math.floor(int53/INT32_MAX)-1
      local rest = int53 - (times+1)*INT32_MAX

      -- number of bytes used by the multiplier (up to 3)
      if times <= INT8_MAX then
         byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_MULT[2])
         bytes[#bytes + 1] = times

      elseif times <= INT16_MAX then
         byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_MULT[3])         
         bytes[#bytes + 1] = band(rshift(times, 8), 0xFF)
         bytes[#bytes + 1] = band(times, 0xFF)
         
      else
         byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_MULT[4])         
         bytes[#bytes + 1] = band(rshift(times, 16), 0xFF)
         bytes[#bytes + 1] = band(rshift(times, 8), 0xFF)
         bytes[#bytes + 1] = band(times, 0xFF)
      end 

      -- number of bytes used by the rest, up to 4
      if rest <= INT8_MAX then
         bytes[#bytes + 1] = rest

      elseif rest <= INT16_MAX then
         byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_REST[2])
         bytes[#bytes + 1] = band(rshift(rest, 8), 0xFF)
         bytes[#bytes + 1] = band(rest, 0xFF)

      elseif rest <= INT24_MAX then
         byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_REST[3])
         bytes[#bytes + 1] = band(rshift(rest, 16), 0xFF)
         bytes[#bytes + 1] = band(rshift(rest, 8), 0xFF)
         bytes[#bytes + 1] = band(rest, 0xFF)

      else
         byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_REST[4])   
         bytes[#bytes + 1] = band(rshift(rest, 24), 0xFF)
         bytes[#bytes + 1] = band(rshift(rest, 16), 0xFF)
         bytes[#bytes + 1] = band(rshift(rest, 8), 0xFF)
         bytes[#bytes + 1] = band(rest, 0xFF)

      end
   end

   if hasDecimal then 
      -- number of bytes used by the decimal (up to 2)
      byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_HAS_DEC)

      if dec <= INT8_MAX then
         bytes[#bytes + 1] = dec
      else
         byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_DEC_BYTES)        
         bytes[#bytes + 1] = band(rshift(dec, 8), 0xFF)
         bytes[#bytes + 1] = band(dec, 0xFF)
      end 
   end

   -- EXTRA
   out[#out + 1] = encode_byte(header, byteExtra)

   -- [<VALUE>]
   for _, byte in ipairs(bytes) do
      out[#out + 1] = encode_byte(header, byte)
   end
end

--[[
   Does the encode of an int53, in the format <{EXTRA}[{VALUE}]?>, See `encode_double_out(header, out, value)`

   @header     {Object} Header reference
   @field      {Object} The reference for the field
   @value      {double} Value that will be serialized
]]
local function encode_double(header, field, value)

   if value == nil or type(value) ~= 'number' or  value == 0 then
      -- ignore
      return '' 
   end

   local out = {
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_DOUBLE, false)
   }

   encode_double_out(header, out, value, false)

   return table.concat(out, '')
end

--[[
   Encodes a double [], in the format [<{EXTRA}[{VALUE}]>], repeating the pattern until all numbers are serialized

   see `encode_double(header, field, value)`

   @header     {Object}    Header reference
   @field      {Object}    The reference for the field
   @values     {double[]}  The values that will be serialized
]]
local function encode_double_array(header, field, values)
   if values == nil or #values == 0 then
      -- ignore
      return '' 
   end
   
   local out = {
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_DOUBLE, true)
   }
   
   local byteExtra   = 0

   local len   = #values
   for i, value in ipairs(values) do
      if value == nil or type(value) ~= 'number' then
         -- invalid
         value = 0
      end

      encode_double_out(header, out, value, i ~= len)
   end

   return table.concat(out, '')
end


--[[
   Decodes the EXTRA of a double, see `encode_double(header, fieldId, value)`

   @byteExtra  {byte} The EXTRA byte that was generated by the `encode_double(header, fieldId, value)` method

   @return {Object} information contained in EXTRA
]]
local function decode_double_extra_byte(byteExtra)
   local extra = {}
   extra.IsNegative  = band(byteExtra, INT_EXTRA_BITMASK_NEGATIVE) ~= 0
   extra.BytesTimes  = rshift(band(byteExtra, DBL_EXTRA_BITMASK_INT_MULT_M), 5)
   extra.IsBig       = extra.BytesTimes > 0
   extra.BytesRest   = rshift(band(byteExtra, DBL_EXTRA_BITMASK_INT_REST_M), 3) + 1
   extra.HasDec      = band(byteExtra, DBL_EXTRA_BITMASK_HAS_DEC) ~= 0
   extra.BytesDec    = rshift(band(byteExtra, DBL_EXTRA_BITMASK_DEC_BYTES), 1) + 1
   extra.HasMore     = band(byteExtra, DBL_EXTRA_BITMASK_HAS_MORE) ~= 0
   return extra
end

--[[
   Decodes the bytes that make up a double, see function `encode_double(header, fieldId, value)`

   @bytes   {byte[]} The bytes that were generated by the `encode_double(header, fieldId, value)` method
   @extra   {Object} Information extracted by the `decode_double_extra_byte(byteExtra)`

   @return {double}
]]
local function decode_double_bytes(bytes, extra) 

   local times, rest, int
   
   local isNegative  = extra.IsNegative
   local timesBytes  = extra.BytesTimes
   local restBytes   = extra.BytesRest
   local decIndex    = 0

   if extra.IsBig then
      decIndex = timesBytes + restBytes + 1
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
   
      int = (times+1) * INT32_MAX + rest
   else
      decIndex = restBytes + 1
      if restBytes == 1 then
         int =  bytes[1]

      elseif restBytes == 2 then
         int =  bor(lshift(bytes[1], 8), bytes[2])

      elseif restBytes == 3 then
         int =  bor(lshift(bytes[1], 16), bor(lshift(bytes[2], 8), bytes[3]))

      else
         int =  bor(lshift(bytes[1], 24), bor(lshift(bytes[2], 16), bor(lshift(bytes[3], 8), bytes[4])))
      end
   end

   local value
   if extra.HasDec then
      local dec
      if extra.BytesDec == 1 then 
         dec = bytes[decIndex]
      else
         dec = bor(lshift(bytes[decIndex], 8), bytes[decIndex+1])
      end
      value = int + dec/10000
   else 
      value = int
   end

   if isNegative then 
      value = -1 * value
   end

   return value
end

local Double = {}
Double.encode_double             = encode_double
Double.decode_double_extra_byte  = decode_double_extra_byte
Double.decode_double_bytes       = decode_double_bytes
Double.encode_double_array       = encode_double_array
return Double
