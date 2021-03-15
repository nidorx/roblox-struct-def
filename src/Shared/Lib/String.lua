local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

local Core = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Core'))
local encode_byte                      = Core.encode_byte
local encode_field                     = Core.encode_field
local FIELD_TYPE_BITMASK_STRING        = Core.FIELD_TYPE_BITMASK_STRING

local Int32 = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Int32'))
local INT8_MAX                      = Int32.INT8_MAX

local STRING_EXTRA_BITMASK_SIZE_FITS   = 128    -- 10000000
local STRING_EXTRA_BITMASK_SIZE        = 127    -- 01111111
local STRING_EXTRA_FIT_SIZE            = 127    --  (2^7) -1   [7 bits]
local STRING_MAX_SIZE                  = 32767  -- (2^15) -1   [15 bits]

--[[
   Faz o ecode de um field do tipo string, no formato <{EXTRA}[{VALUE}]?>

   {VALUE} Aceita no máximo 32767 caracteres UTF-8

   {EXTRA}
      1 1 1 1 1 1 1 1
      | |           |
      | +-----------+--- 7 bit   Primeira parte da string, caso tamanho seja maior que 127, usa um segundo byte para 
      |                             abrigar o tamanho da string        
      +----------------- 1 bit   tamanho da string cabe nos proximos bits (se tamanho <= 127 = ((2^7) -1))

   [{VALUE}]
      Até 4 bytes do numero sendo serializado
      Quando número é <= 63 (2^6)-1 o valor já é serializado no {EXTRA}

   @header     {Object} Referencia para o header
   @field      {Object} A referencia para o campo
   @value      {int32}  Valor que será serializado
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
   Faz o decode do primeiro byte do EXTRA de uma string, ver `encode_string(header, field, value)`

   @byteExtra {byte} Primeiro byte do `encode_string(header, field, value)`
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
   Faz o decode do segundo byte do EXTRA de uma string, ver `encode_string(header, field, value)`

   @secondByteExtra     {byte} Segundo byte do `encode_string(header, field, value)`
   @decodedExtraFirst   {byte} Retorno do `decode_string_extra_byte_first(firstByteExtra)`
]]
local function decode_string_extra_byte_second(secondByteExtra, decodedExtraFirst)
   decodedExtraFirst.Size = bor(lshift(decodedExtraFirst.Byte, 8), secondByteExtra)
   return decodedExtraFirst
end


--[[
   Faz o ecode de um field do tipo string[], no formato {EXTRA}[<{EXTRA}[{VALUE}]?>]

   {EXTRA}
      1 byte, informa quantas strings existem no array. Máximo de 255

   [<{EXTRA}[{VALUE}]?>] ver método `encode_string`
      

   @header     {Object} Referencia para o header
   @field      {Object} A referencia para o campo
   @value      {int32}  Valor que será serializado
]]
local function encode_string_array(header, field, values)
   if values == nil or table.getn(values) == 0 then
      -- invalid, ignore
      return ''
   end

   local count = math.min(INT8_MAX, #values)

   local out = {
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_STRING, true),
      -- primeiro EXTRA é a quantidade de itens que o array possui
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


local Module = {}
Module.encode_string                   = encode_string
Module.decode_string_extra_byte_first  = decode_string_extra_byte_first
Module.decode_string_extra_byte_second = decode_string_extra_byte_second
Module.encode_string_array             = encode_string_array
Module.STRING_MAX_SIZE                 = STRING_MAX_SIZE
return Module
