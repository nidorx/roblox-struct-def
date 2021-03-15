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
local INT53_MAX                     = Int32.INT53_MAX
local INT_EXTRA_BITMASK_NEGATIVE    = Int32.INT_EXTRA_BITMASK_NEGATIVE
local INT_EXTRA_BITMASK_BYTE_COUNT  = Int32.INT_EXTRA_BITMASK_BYTE_COUNT
local INT_EXTRA_BITMASK_NUM_BYTES   = Int32.INT_EXTRA_BITMASK_NUM_BYTES


local INT53_EXTRA_BITMASK_IS_BIG       = 32  -- 00100000
local INT53_EXTRA_BITMASK_HAS_MORE     = 16  -- 00010000
local INT53_EXTRA_BITMASK_BYTE_COUNT   = 3   -- 00000011

-- quantos bytes [chars] é usado pelo resto do int53 na sequencia (4 valores)
local INT53_EXTRA_BITMASK_NUM_BYTES = {
   0, -- 00000000   = 1 byte
   1, -- 00000001   = 2 bytes
   2, -- 00000010   = 3 bytes
   3  -- 00000011   = 4 bytes
}

--[[
   Lógica comum aos métodos encode_int53 e encode_int53_array

   Faz o encode de um int53, no formato <{EXTRA}[{VALUE}]?>

   {EXTRA}
      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | | |
      | | | | | | +-+--- 2 bits  quantos bytes [chars] é usado pelo int32 do resto (4 valores)
      | | | | +-+------- 2 bits  quantos bytes [chars] é usado pelo int32 do multiplicador (4 valores)
      | | | +----------- 1 bits  HAS_MORE? Usado pelo encode_int53_array para indicar continuidade
      | | +------------- 1 bits  Número é maior que 32 bits, caso positivo foi quebrado em times e rest
      | +--------------- 1 bit   descartado
      +----------------- 1 bit   0 = POSITIVO, 1 = NEGATIVO

   [{VALUE}]
      Até 7 bytes do numero sendo serializado
      Quando número é <= 63 (2^6)-1 o valor já é serializado no {EXTRA}

   @header     {Object} Referencia para o header
   @out        {array}  O output sendo gerado
   @value      {int32}  Valor que será serializado
]]
local function encode_int53_out(header, out, value, hasMore)
   local byteExtra = 0
   if value < 0 then 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NEGATIVE)
   end
   
   if hasMore then 
      byteExtra = bor(byteExtra, INT53_EXTRA_BITMASK_HAS_MORE)
   end

   -- normaliza o número para o limite do int32
   value = math.min(INT53_MAX, math.max(0, math.abs(value)))

   if value <= INT8_MAX then
      -- (2^8) -1  [1 byte] = "11111111"

      -- usa 1 byte 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[1])
      out[#out + 1] = encode_byte(header, byteExtra)

      -- 1 byte
      out[#out + 1] = encode_byte(header, value)
   
   elseif value <= INT16_MAX then
      -- (2^16) -1  [2 bytes] = "11111111 11111111"

      -- usa 2 bytes 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[2])
      out[#out + 1] = encode_byte(header, byteExtra)

      -- 2 bytes
      out[#out + 1] = encode_byte(header, band(rshift(value, 8), 0xFF))
      out[#out + 1] = encode_byte(header, band(value, 0xFF))

   elseif value <= INT24_MAX then
      -- (2^24) -1  [3 bytes] = "11111111 11111111 11111111"

      -- usa 3 bytes 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[3])
      out[#out + 1] = encode_byte(header, byteExtra)

      -- 3 bytes
      out[#out + 1] = encode_byte(header, band(rshift(value, 16), 0xFF))
      out[#out + 1] = encode_byte(header, band(rshift(value, 8), 0xFF))
      out[#out + 1] = encode_byte(header, band(value, 0xFF))

   elseif value <= INT32_MAX then
      -- (2^32) -1  [4 bytes] = "11111111 11111111 11111111 11111111"

      -- usa 3 bytes 
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[4])
      out[#out + 1] = encode_byte(header, byteExtra)

      -- 4 bytes
      out[#out + 1] = encode_byte(header, band(rshift(value, 24), 0xFF))
      out[#out + 1] = encode_byte(header, band(rshift(value, 16), 0xFF))
      out[#out + 1] = encode_byte(header, band(rshift(value, 8), 0xFF))
      out[#out + 1] = encode_byte(header, band(value, 0xFF))

   else
      -- número maior que 32 bits, não é possível fazer manipulação usando a lib bit32, necessário quebrar o número
      -- desse modo cabe em até 6 bytes

      -- número é grande
      byteExtra = bor(byteExtra, INT53_EXTRA_BITMASK_IS_BIG)

      local times = math.floor(value/INT32_MAX)-1
      local rest = value - (times+1)*INT32_MAX

      local bytes = {}

      -- numero de bytes usados pelo multiplicador (até 2)
      if times <= INT8_MAX then
         bytes[#bytes + 1] = times
         
      else
         byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_NUM_BYTES[2])         
         bytes[#bytes + 1] = band(rshift(times, 8), 0xFF)
         bytes[#bytes + 1] = band(times, 0xFF)
      end 

      -- número de bytes usado pela sobra, até 4
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
   Faz o encode de um int53, no formato <{EXTRA}[{VALUE}]?>, ver `encode_int53_out(header, out, value)`

   @header     {Object} Referencia para o header
   @field      {Object} A referencia para o campo
   @value      {int32}  Valor que será serializado
]]
local function encode_int53(header, field, value)

   if value == nil or type(value) ~= 'number' then
      -- invalid, ignore
      return '' 
   end

   -- faz arredondamento do número, caso receba double
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
   Faz a decodifiação do EXTRA de um int53, ver `encode_int53(header, fieldId, value)`

   @byteExtra  {int8} O {EXTRA} byte que foi gerado pelo método `encode_int53(header, fieldId, value)`

   @return {object} informações contidas no {EXTRA}
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
   Faz a decodifiação dos bytes que compoem um int53, apenas quando é BIG, ver função `encode_int53(header, fieldId, value)` 

   @bytes      {int8[]} O bytes que foram gerados pelo método `encode_int53(header, fieldId, value)`
   @isNegative {bool}   O valor é negativo (informação está no {EXTRA} byte)
   @timesLen   {number} Quantos bytes faz parte do multiplicador x32
   @restLen    {number} Quantos bytes faz parte do resto

   @return {int53}
]]
local function decode_int53_bytes(bytes, isNegative, timesBytes, restBytes)
   local times, rest, value

   if timesBytes == 1 then
      times = bytes[1]
   else
      times = bor(lshift(bytes[1], 8), bytes[2])
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
   Faz o encode de um int53[], no formato [<{EXTRA}[{VALUE}]>], repetindo o padrão até que todos os numeros sejam 
   serializados

   {EXTRA}
      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | | |
      | | | | | | +-+--- 2 bits  quantos bytes [chars] é usado pelo int32 do resto (4 valores)
      | | | | +-+------- 2 bits  quantos bytes [chars] é usado pelo int32 do multiplicador (4 valores)
      | | | +----------- 1 bits  HAS MORE? Indica que possui mais números na sequencia
      | | +------------- 1 bits  Número é maior que 32 bits, caso positivo foi quebrado em times e rest
      | +--------------- 1 bit   número cabe nos proximos bits? Se número for <= 63 (2^6) o seu conteúdo já é
      |                          formado pelos proximos bits.
      +----------------- 1 bit   0 = POSITIVO, 1 = NEGATIVO

   [{VALUE}]
      Até 6 bytes por numero sendo serializado

   @header     {Object}    Referencia para o header
   @field      {Object}    A referencia para o campo
   @values     {int53[]}   Os valores que serão serializados
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
   
      -- faz arredondamento do número, caso receba double
      value = math.round(value)

      encode_int53_out(header, out, value, i ~= len)
   end

   return table.concat(out, '')
end

local Module = {}
Module.encode_int53_out           = encode_int53_out
Module.encode_int53         = encode_int53
Module.decode_int53_extra_byte    = decode_int53_extra_byte
Module.decode_int53_bytes         = decode_int53_bytes
Module.encode_int53_array   = encode_int53_array
return Module
