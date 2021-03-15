local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

local Core = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Core'))
local encode_byte                      = Core.encode_byte
local encode_field                     = Core.encode_field
local FIELD_TYPE_BITMASK_BOOL          = Core.FIELD_TYPE_BITMASK_BOOL
local FIELD_TYPE_BITMASK_BOOL_ARRAY    = Core.FIELD_TYPE_BITMASK_BOOL_ARRAY


local BOOL_ARRAY_BITMASK_COUNT      = 192 -- 11000000
local BOOL_ARRAY_BITMASK_VALUES     = 16  -- 00111100
local BOOL_ARRAY_BITMASK_HAS_MORE   = 1   -- 00000001

-- A mascara para determinar quntos booleans existem neste byte
local BOOL_ARRAY_BITMASK_COUNT_VALUES = {
   0,    -- 00000000 = 1 bool
   64,   -- 01000000 = 2 bool
   128,  -- 10000000 = 3 bool
   192   -- 11000000 = 4 bool
}

-- A mascara de valores para o array de bool
local BOOL_ARRAY_BITMASK_VALUE = {
   32, -- 000100000
   16, -- 000010000
   8,  -- 000001000
   4   -- 000000100
}

--[[
   quando bool, usa o bit IS_ARRAY para salvar o valor

   1 1 1 1 1 1 1 1
   |   | | |     |
   |   | | +-----+--- 4 bits  FIELD_ID
   |   | |            
   |   | +----------- 1 bit   IS_ARRAY -> FIELD_TYPE_BITMASK_BOOL (TRUE ou FALSE)
   +---+------------- 3 bits  FIELD_TYPE

   @header     {Object} Referencia para o header
   @field      {Object} A referencia para o campo
   @value      {bool}   Valor sendo serializado
]]
local function encode_field_bool(header, field, value)
   return encode_field(header, field.Id, FIELD_TYPE_BITMASK_BOOL, value == true)
end

--[[
   Um arrray de booleans é encodado no seguinte formato

   1 1 1 1 1 1 1 1
   | | |     | | |
   | | |     | | +--- 1 bit   TEM MAIS? Caso positivo, o proximo byte também  faz parte do array, mesma estrutura
   | | |     | | 
   | | |     | +----- 1 bit   descartado
   | | |     | 
   | | +-----+------- 4 bits  que podem fazer parte do array
   | |
   +-+--------------- 2 bit   determina quantos bits seguintes fazem parte do array (2 bits = 4 valores) 

   @header     {Object} Referencia para o header
   @field      {Object} A referencia para o campo
   @value      {bool[]} Valores que estão sendo serializados
]]
local function encode_field_bool_array(header, field, value)

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
            -- só faz encode do cabeçalho se houver dados
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

   -- Existem itens residuais ?
   if index > 0 then
      -- count
      byte = bor(byte, BOOL_ARRAY_BITMASK_COUNT_VALUES[index])

      if #out == 0 then
         -- só faz encode do cabeçalho se houver dados
         out[#out + 1] = encode_field(header, field.Id, FIELD_TYPE_BITMASK_BOOL_ARRAY, true)
      end

      out[#out + 1]  = encode_byte(header, byte)
   end

   return table.concat(out, '')
end

--[[
   Faz a decodifiação de um byte encodado pelo método `encode_field_bool_array(header, fieldId, value)`

   1 1 1 1 1 1 1 1
   | | |     | | |
   | | |     | | +--- 1 bit   TEM MAIS? Caso positivo, o proximo byte também  faz parte do array, mesma estrutura
   | | |     | | 
   | | |     | +----- 1 bit   descartado
   | | |     | 
   | | +-----+------- 4 bits  que podem fazer parte do array
   | |
   +-+--------------- 2 bit   determina quantos bits seguintes fazem parte do array (2 bits = 4 valores) 

   @byte    {int8}         O byte que foi gerado pelo método `encode_field_bool_array(header, fieldId, value)`
   @array   {Array<bool>}  O array que irá receber os dados processados

   @return {bool} True se tiver mais itens para ser proessado na sequencia

]]
local function decode_bool_array_byte(byte, array)
   local count = rshift(band(byte, BOOL_ARRAY_BITMASK_COUNT), 6) + 1

   for index = 1, count do
      table.insert(array, band(byte, BOOL_ARRAY_BITMASK_VALUE[index]) > 0)
   end

   -- has more
   return band(byte, BOOL_ARRAY_BITMASK_HAS_MORE) > 0
end



local Module = {}
Module.encode_field_bool         = encode_field_bool
Module.encode_field_bool_array   = encode_field_bool_array
Module.decode_bool_array_byte    = decode_bool_array_byte
return Module
