local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

local Core = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Core'))
local encode_byte                      = Core.encode_byte
local encode_field                     = Core.encode_field
local FIELD_TYPE_BITMASK_STRING        = Core.FIELD_TYPE_BITMASK_STRING

local Int32 = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Int32'))
local INT8_MAX                         = Int32.INT8_MAX

local STRING_EXTRA_BITMASK_SIZE_FITS   = 128    -- 10000000
local STRING_EXTRA_BITMASK_SIZE        = 127    -- 01111111
local STRING_EXTRA_FIT_SIZE            = 127    --  (2^7) -1   [7 bits]
local STRING_MAX_SIZE                  = 32767  -- (2^15) -1   [15 bits]

--[[
   Encodes a string-type field, in <{EXTRA}[{VALUE}]?> format 

   [{VALUE}] Accepts a maximum of 32767 UTF-8 characters

   {EXTRA}
      1 1 1 1 1 1 1 1
      | |           |
      | +-----------+--- 7 bit   First part of the string, if length is greater than 127, uses a second byte to 
      |                             accommodate the length of the string     
      +----------------- 1 bit   string size fits the next bits (if size <= 127 = ((2 ^ 7) -1))

   @header     {Object} Header reference
   @field      {Object} The reference for the field
   @value      {String} Value that will be serialized
]]
local function encode_string(header, field, value)
   if value == nil or type(value) ~= 'string' then
      -- invalid, ignore
      return ''
   end

   local len = utf8.len(value)
   if len == 0 then 
      -- empty, ignore
      return ''
   end

   local maxLength = field.MaxLength
   if len > maxLength then 
      value = string.sub(value, 1, maxLength)
      len   = maxLength
   end

   local out = {
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_STRING, false)
   }

   local byteExtra = 0
   if len <= STRING_EXTRA_FIT_SIZE then 
      byteExtra = bor(byteExtra, len)
      byteExtra = bor(byteExtra, STRING_EXTRA_BITMASK_SIZE_FITS)
      out[#out + 1] = encode_byte(header, byteExtra)
   else
      -- 2 bytes
      byteExtra = len
      out[#out + 1] = encode_byte(header, band(rshift(len, 8), 0xFF))
      out[#out + 1] = encode_byte(header, band(len, 0xFF))
   end

   out[#out + 1] = value

   return table.concat(out, '')
end

--[[
   Decode the first EXTRA byte of a string, see `encode_string (header, field, value)`

   @firstByteExtra {byte} First byte of `encode_string (header, field, value)`
]]
local function decode_string_extra_byte_first(firstByteExtra)
   local out = {}

   if band(firstByteExtra, STRING_EXTRA_BITMASK_SIZE_FITS) ~= 0 then 
      out.SizeFits   = true
      out.Size       = band(firstByteExtra, STRING_EXTRA_BITMASK_SIZE)
   else
      out.SizeFits   = false
      out.Byte       = band(firstByteExtra, STRING_EXTRA_BITMASK_SIZE)
   end

   return out
end

--[[
   Decode the EXTRA second byte of a string, see `encode_string(header, field, value)`

   @secondByteExtra     {byte} Second byte of `encode_string(header, field, value)`
   @decodedExtraFirst   {byte} Return of `decode_string_extra_byte_first(firstByteExtra)`
]]
local function decode_string_extra_byte_second(secondByteExtra, decodedExtraFirst)
   decodedExtraFirst.Size = bor(lshift(decodedExtraFirst.Byte, 8), secondByteExtra)
   return decodedExtraFirst
end


--[[
   Does the ecode of a field of type string [], in the format {EXTRA}[<{EXTRA}[{VALUE}]?>]

   {EXTRA}
      1 byte, tells how many strings are in the array. 255 maximum

   [<{EXTRA}[{VALUE}]?>] See `encode_string(header, field, value)`
      

   @header     {Object}    Header reference
   @field      {Object}    The reference for the field
   @value      {String[]}  Value that will be serialized
]]
local function encode_string_array(header, field, values)
   if values == nil or table.getn(values) == 0 then
      -- invalid, ignore
      return ''
   end

   local count = math.min(INT8_MAX, #values)

   local out = {
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_STRING, true),
      -- first EXTRA is the number of items that the array has
      encode_byte(header, count)
   }

   local maxLength = field.MaxLength

   for i = 1, count do
      local value = values[i]

      if value == nil or type(value) ~= 'string' then
         value =  ''
      end
   
      local len = utf8.len(value)   
      if len > maxLength then 
         value = string.sub(value, 1, maxLength)
         len   = maxLength
      end
   
      local byteExtra = 0
      if len <= STRING_EXTRA_FIT_SIZE then 
         byteExtra = len
         byteExtra = bor(byteExtra, STRING_EXTRA_BITMASK_SIZE_FITS)
         out[#out + 1] = encode_byte(header, byteExtra)
      else
         -- 2 bytes
         byteExtra = len
         out[#out + 1] = encode_byte(header, band(rshift(byteExtra, 8), 0xFF))
         out[#out + 1] = encode_byte(header, band(byteExtra, 0xFF))
      end
   
      out[#out + 1] = value
   end

   return table.concat(out, '')
end


local String = {}
String.encode_string                   = encode_string
String.decode_string_extra_byte_first  = decode_string_extra_byte_first
String.decode_string_extra_byte_second = decode_string_extra_byte_second
String.encode_string_array             = encode_string_array
String.STRING_MAX_SIZE                 = STRING_MAX_SIZE
return String
