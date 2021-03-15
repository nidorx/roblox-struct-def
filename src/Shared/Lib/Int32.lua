local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

local Core = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Core'))
local encode_byte                      = Core.encode_byte
local encode_field                     = Core.encode_field
local FIELD_TYPE_BITMASK_INT32         = Core.FIELD_TYPE_BITMASK_INT32

local INT_EXTRA_BITMASK_NEGATIVE       = 128 -- 10000000
local INT_EXTRA_BITMASK_IT_FITS        = 64  -- 01000000
local INT_EXTRA_BITMASK_VALUE          = 63  -- 00111111
local INT_EXTRA_BITMASK_BYTE_COUNT     = 12  -- 00001100

-- quantos bytes [chars] é usado pelo int32 na sequencia (4 valores)
-- Usado pelo int53 para determinar o multiplicador
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
local INT53_MAX  = 281474976710655     -- (2^48) -1  [6 bytes]

--[[
   Faz o encode de um int32, no formato <{EXTRA}[{VALUE}]?>

   {EXTRA}
      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | | |
      | | | | | | +-+--- 2 bits  descartado caso numero maior que 64
      | | | | +-+------- 2 bits  quantos bytes [chars] é usado pelo int32 na sequencia (4 valores)
      | | +-+----------- 2 bits  descartado caso numero maior que 64
      | +--------------- 1 bit   número cabe nos proximos bits? Se número for <= 63 (2^6) o seu conteúdo já é
      |                          formado pelos proximos bit. Caso negativo, valida proximos 2 bits
      +----------------- 1 bit   0 = POSITIVO, 1 = NEGATIVO

   [{VALUE}]
      Até 4 bytes do numero sendo serializado
      Quando número é <= 63 (2^6)-1 o valor já é serializado no {EXTRA}

   @header     {Object} Referencia para o header
   @field      {Object} A referencia para o campo
   @value      {int32}  Valor que será serializado
]]
local function encode_field_int32(header, field, value)

   if value == nil or type(value) ~= 'number' then
      -- invalid, ignore
      return '' 
   end

   -- faz arredondamento do número, caso recebe double
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

   -- normaliza o número para o limite do int32
   value = math.min(INT32_MAX, math.max(0, math.abs(value)))

   if value <= INT6_MAX then
      -- número cabe nos proximos bits

      byteExtra = bor(byteExtra, value)
      byteExtra = bor(byteExtra, INT_EXTRA_BITMASK_IT_FITS)
      
      out[#out + 1] = encode_byte(header, byteExtra)

   elseif value <= INT8_MAX then
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

   else
      -- (2^32) -1  [4 bytes] = "11111111 11111111 11111111 11111111"

      -- usa 3 bytes 
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
   Faz a decodifiação do EXTRA de um int32, ver `encode_field_int32(header, fieldId, value)`

   @byteExtra  {int8} O {EXTRA} byte que foi gerado pelo método `encode_field_int32(header, fieldId, value)`

   @return {object} informações contidas no {EXTRA}
]]
local function decode_int32_extra_byte(byteExtra)
   local out = {}   
   local isNegative = band(byteExtra, INT_EXTRA_BITMASK_NEGATIVE) ~= 0

   if band(byteExtra, INT_EXTRA_BITMASK_IT_FITS) ~= 0 then 
      -- valor cabe nos 4 últimos bits
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
   Faz a decodifiação dos bytes que compoem um int32, ver função `encode_field_int32(header, fieldId, value)` 

   @bytes      {int8[]} O bytes que foram gerados pelo método `encode_field_int32(header, fieldId, value)`
   @isNegative {bool}   O valor é negativo (informação está no {EXTRA} byte)

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

-- quantos bytes [chars] é usado pelo int32 na sequencia (4 valores)
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
   Faz o encode de um int32[], no formato [<{EXTRA}[{VALUE}]>], repetindo o padrão até que todos os numeros sejam 
   serializados

   {EXTRA}
      Existe 1 extra para cada dois números

      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | | +--- 1 bit   TEM MAIS? Caso positivo, o proximo byte também  faz parte do array, mesma estrutura
      | | | | | | +----- 1 bit   2º int32 na sequencia é 0 = POSITIVO, 1 = NEGATIVO
      | | | | +-+------- 2 bits  2º int32 na sequencia quantos bytes [chars] é usado 
      | | | +----------- 1 bit   TEM MAIS
      | | +------------- 1 bit   1º int32 na sequencia é 0 = POSITIVO, 1 = NEGATIVO
      +-+--------------- 2 bits  1º int32 na sequencia quantos bytes [chars] é usado 

   [{VALUE}]
      Até 4 bytes por numero sendo serializado

   @header     {Object}    Referencia para o header
   @field      {Object}    A referencia para o campo
   @values     {int32[]}   Os valores que serão serializados
]]
local function encode_field_int32_array(header, field, values)
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
   
      -- faz arredondamento do número, caso recebe double
      value = math.round(value)
   
      if value < 0 then
         byteExtra = bor(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NEGATIVE[index])
      end

      -- HAS MORE
      if i < len then 
         byteExtra = bor(byteExtra, INT32_ARRAY_EXTRA_BITMASK_HAS_MORE[index])
      end
   
      -- normaliza o número para o limite do int32
      value = math.min(INT32_MAX, math.max(0, math.abs(value)))
   
      if value <= INT8_MAX then
         -- (2^8) -1  [1 byte] = "11111111"
   
         -- 1 byte
         bytes[#bytes + 1] = value
      
      elseif value <= INT16_MAX then
         -- (2^16) -1  [2 bytes] = "11111111 11111111"
   
         -- usa 2 bytes 
         byteExtra = bor(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NUM_BYTES[index][2])
   
         -- 2 bytes
         bytes[#bytes + 1] = band(rshift(value, 8), 0xFF)
         bytes[#bytes + 1] = band(value, 0xFF)
   
      elseif value <= INT24_MAX then
         -- (2^24) -1  [3 bytes] = "11111111 11111111 11111111"
   
         -- usa 3 bytes 
         byteExtra = bor(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NUM_BYTES[index][3])
   
         -- 3 bytes
         bytes[#bytes + 1] = band(rshift(value, 16), 0xFF)
         bytes[#bytes + 1] = band(rshift(value, 8), 0xFF)
         bytes[#bytes + 1] = band(value, 0xFF)
   
      else
         -- (2^32) -1  [4 bytes] = "11111111 11111111 11111111 11111111"
   
         -- usa 3 bytes 
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
   Faz a decodifiação do EXTRA de um int32, ver `encode_field_int32_array(header, fieldId, value)`

   @byteExtra  {int8} O {EXTRA} byte que foi gerado pelo método `encode_field_int32_array(header, fieldId, value)`

   @return {object} informações contidas no {EXTRA}
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


local Module = {}
Module.encode_field_int32            = encode_field_int32
Module.decode_int32_extra_byte       = decode_int32_extra_byte
Module.decode_int32_bytes            = decode_int32_bytes
Module.encode_field_int32_array      = encode_field_int32_array
Module.decode_int32_array_extra_byte = decode_int32_array_extra_byte
Module.INT6_MAX                      = INT6_MAX
Module.INT8_MAX                      = INT8_MAX
Module.INT16_MAX                     = INT16_MAX
Module.INT24_MAX                     = INT24_MAX
Module.INT32_MAX                     = INT32_MAX
Module.INT53_MAX                     = INT53_MAX
Module.INT_EXTRA_BITMASK_NEGATIVE    = INT_EXTRA_BITMASK_NEGATIVE
Module.INT_EXTRA_BITMASK_IT_FITS     = INT_EXTRA_BITMASK_IT_FITS
Module.INT_EXTRA_BITMASK_VALUE       = INT_EXTRA_BITMASK_VALUE
Module.INT_EXTRA_BITMASK_BYTE_COUNT  = INT_EXTRA_BITMASK_BYTE_COUNT
Module.INT_EXTRA_BITMASK_NUM_BYTES   = INT_EXTRA_BITMASK_NUM_BYTES
return Module
