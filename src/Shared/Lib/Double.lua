local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

--[[
   var n = 5.666000
   var int = Math.floor(n)
   var dec = Math.min(Math.floor((n - int) * 100000), 65535)
   console.log(n, int, int.toString(2), dec, dec.toString(2))
   var n2 = int + Math.min(dec/100000, 65535)
   console.log(n2)

   https://en.wikipedia.org/wiki/Double-precision_floating-point_format
]]

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
local INT53_MAX                     = Int32.INT53_MAX
local INT_EXTRA_BITMASK_NEGATIVE    = Int32.INT_EXTRA_BITMASK_NEGATIVE
local INT_EXTRA_BITMASK_BYTE_COUNT  = Int32.INT_EXTRA_BITMASK_BYTE_COUNT
local INT_EXTRA_BITMASK_NUM_BYTES   = Int32.INT_EXTRA_BITMASK_NUM_BYTES

local DBL_EXTRA_BITMASK_IS_BIG      = 64  -- 01000000
local DBL_EXTRA_BITMASK_INT_MULT    = 32  -- 00100000
local DBL_EXTRA_BITMASK_INT_REST_M  = 24  -- 00011000
local DBL_EXTRA_BITMASK_HAS_DEC     = 4   -- 00000100
local DBL_EXTRA_BITMASK_DEC_BYTES   = 2   -- 00000010
local DBL_EXTRA_BITMASK_HAS_MORE    = 1   -- 00000001

-- quantos bytes [chars] é usado pelo int32 do resto (4 valores)
local DBL_EXTRA_BITMASK_INT_REST = {
   0,    -- 00000000   = 1 byte
   8,    -- 00001000   = 2 bytes
   16,   -- 00010000   = 3 bytes
   24    -- 00011000   = 4 bytes
}

--[[
   Lógica comum aos métodos encode_int53 e encode_int53_array

   Faz o encode de um double, no formato <{EXTRA}[{VALUE}]?>

   {EXTRA}
      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | | |
      | | | | | | | +--- 1 bits  HAS_MORE? Usado pelo encode_int53_array para indicar continuidade
      | | | | | | +----- 1 bit   quantos bytes [chars] é usado pelos decimais (2 valores)
      | | | | | +------- 1 bit   Número possui decimais
      | | | +-+--------- 2 bits  quantos bytes [chars] é usado pelo int32 do resto (4 valores)
      | | +------------- 1 bits  quantos bytes [chars] é usado pelo int32 do multiplicador (2 valores), quando BIG
      | +--------------- 1 bits  Número é maior que 32 bits, caso positivo foi quebrado em times e rest
      +----------------- 1 bit   0 = POSITIVO, 1 = NEGATIVO

   [{VALUE}]
      Até 8 bytes do numero sendo serializado, sendo
         - até 2 bytes para o multiplicador da parte inteira
         - até 4 bytes para o resto da parte inteira
         - até 2 bytes para os decimais (limitado portanto até 65535)

   @header     {Object} Referencia para o header
   @out        {array}  O output sendo gerado
   @value      {int32}  Valor que será serializado
   @hasMore    {bool}   Quando array, permite definir se existem mais números na sequencia
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

   -- normaliza o número para o limite do int53
   value = math.abs(value)
   local int53 = math.floor(value)
   
   if int53 ~= value then
      hasDecimal = true 
   end
   
   int53 = math.min(INT53_MAX, math.max(0, int53))

   local bytes = {}

   if int53 <= INT8_MAX then
      -- (2^8) -1  [1 byte] = "11111111"

      -- 1 byte
      bytes[#bytes + 1] = int53
   
   elseif int53 <= INT16_MAX then
      -- (2^16) -1  [2 bytes] = "11111111 11111111"

      -- usa 2 bytes 
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
      -- número maior que 32 bits, não é possível fazer manipulação usando a lib bit32, necessário quebrar o número
      -- desse modo cabe em até 6 bytes

      -- número é grande
      byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_IS_BIG)

      local times = math.floor(int53/INT32_MAX)-1
      local rest = int53 - (times+1)*INT32_MAX

      -- numero de bytes usados pelo multiplicador (até 2)
      if times <= INT8_MAX then
         bytes[#bytes + 1] = times
         
      else
         byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_INT_MULT)         
         bytes[#bytes + 1] = band(rshift(times, 8), 0xFF)
         bytes[#bytes + 1] = band(times, 0xFF)
      end 

      -- número de bytes usado pela sobra, até 4
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
      -- numero de bytes usados pelo decimal (até 2)
      byteExtra = bor(byteExtra, DBL_EXTRA_BITMASK_HAS_DEC)

      local dec = math.floor((value - int53) * 10000)

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
   Faz o encode de um int53, no formato <{EXTRA}[{VALUE}]?>, ver `encode_double_out(header, out, value)`

   @header     {Object} Referencia para o header
   @field      {Object} A referencia para o campo
   @value      {double} Valor que será serializado
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
   Faz o encode de um double[], no formato [<{EXTRA}[{VALUE}]>], repetindo o padrão até que todos os numeros sejam 
   serializados

   ver `encode_double(header, field, value)`

   @header     {Object}    Referencia para o header
   @field      {Object}    A referencia para o campo
   @values     {double[]}  Os valores que serão serializados
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
   Faz a decodifiação do EXTRA de um double, ver `encode_double(header, fieldId, value)`

   @byteExtra  {int8} O {EXTRA} byte que foi gerado pelo método `encode_double(header, fieldId, value)`

   @return {object} informações contidas no {EXTRA}
]]
local function decode_double_extra_byte(byteExtra)
   local extra = {}
   extra.IsNegative  = band(byteExtra, INT_EXTRA_BITMASK_NEGATIVE) ~= 0
   extra.IsBig       = band(byteExtra, DBL_EXTRA_BITMASK_IS_BIG)  ~= 0
   extra.BytesTimes  = rshift(band(byteExtra, DBL_EXTRA_BITMASK_INT_MULT), 5) + 1
   extra.BytesRest   = rshift(band(byteExtra, DBL_EXTRA_BITMASK_INT_REST_M), 3) + 1
   extra.HasDec      = band(byteExtra, DBL_EXTRA_BITMASK_HAS_DEC) ~= 0
   extra.BytesDec    = rshift(band(byteExtra, DBL_EXTRA_BITMASK_DEC_BYTES), 1) + 1
   extra.HasMore     = band(byteExtra, DBL_EXTRA_BITMASK_HAS_MORE) ~= 0
   return extra
end

--[[
   Faz a decodifiação dos bytes que compoem um double, ver função `encode_double(header, fieldId, value)` 

   @bytes   {byte[]} O bytes que foram gerados pelo método `encode_double(header, fieldId, value)`
   @extra   {object} As informações extraidas pelo método `decode_double_extra_byte(byteExtra)`

   @return {double}
]]
local function decode_double_bytes(bytes, extra) 

   --[[
      var n = 1.61325535
      var int = Math.floor(n)
      var dec = Math.min(Math.floor((n - int) * 100000), 65535)
      console.log(n, int, int.toString(2), dec, dec.toString(2))
      var n2 = int + Math.min(dec/100000, 65535)
      console.log(n2)

      https://en.wikipedia.org/wiki/Double-precision_floating-point_format
   ]]

   local times, rest, int
   
   local isNegative  = extra.IsNegative
   local timesBytes  = extra.BytesTimes
   local restBytes   = extra.BytesRest
   local decIndex    = 0

   if extra.IsBig then
      decIndex = timesBytes + restBytes + 1
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

local Module = {}
Module.encode_double             = encode_double
Module.decode_double_extra_byte  = decode_double_extra_byte
Module.decode_double_bytes       = decode_double_bytes
Module.encode_double_array       = encode_double_array
return Module
