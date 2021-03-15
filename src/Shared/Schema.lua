--[[
   Roblox Schema v1.0.0 [2021-02-28 22:10]

   ...

   https://github.com/nidorx/roblox-schema

   Discussions about this script are at https://devforum.roblox.com/t/FORUM_ID

   ------------------------------------------------------------------------------

   MIT License

   Copyright (c) 2021 Alex Rodin

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.
]]
local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift


local serialize

--[[
   Sistema de serialização inspirado no protobuf, com foco em saídas UTF-8
]]

-- todos os schemas registrados
local SCHEMA_BY_ID = {}

-- os caracteres usados para encodar os valores numéricos e marcadores dos objetos
local CHARS = {
   "#","$","%","&","'","(",")","*","+",",","-",".","/",
   "0","1","2","3","4","5","6","7","8","9",":",";","<",
   "=",">","?","@","A","B","C","D","E","F","G","H","I",
   "J","K","L","M","N","O","P","Q","R","S","T","U","V",
   "W","X","Y","Z","[","]","^","_","`","a","b","c","d",
   "e","f","g","h","i","j","k","l","m","n","o","p","q",
   "r","s","t","u","v","w","x","y","z","{","|","}","~"
}
CHARS[0] = '!' -- indice no lua começa em 1, resolvido

-- indice reverso, usado para realizar o decode
local CHARS_BY_KEY = {}
for i =0, table.getn(CHARS) do
   CHARS_BY_KEY[CHARS[i]] = i
end

-- O marcador do fim de schema (para schemas aninhados)  (00111100, 60, <)
local HEADER_END_MARK = '<'

-- os tipos de campos possíveis
local FIELD_TYPE_BITMASK_BOOL        = 0   -- 00000000
local FIELD_TYPE_BITMASK_BOOL_ARRAY  = 32  -- 00100000
local FIELD_TYPE_BITMASK_INT32       = 64  -- 01000000
local FIELD_TYPE_BITMASK_INT53       = 96  -- 01100000
local FIELD_TYPE_BITMASK_DOUBLE      = 128 -- 10000000
local FIELD_TYPE_BITMASK_STRING      = 160 -- 10100000
local FIELD_TYPE_BITMASK_SCHEMA      = 192 -- 11000000
local FIELD_TYPE_BITMASK_SCHEMA_END  = 224 -- 11100000 - Marca o fim de um schema

--[[
   Apenas para depuração e logs, obtém o nome do field a partir do tipo
]]
local function get_field_type_name(fieldType, isArray)

   if fieldType == FIELD_TYPE_BITMASK_BOOL then 
      return 'bool'

   elseif fieldType == FIELD_TYPE_BITMASK_BOOL_ARRAY then 
      return 'bool[]'

   elseif fieldType == FIELD_TYPE_BITMASK_INT32 then 
      if isArray then 
         return 'int32[]'
      else
         return 'int32'
      end
   elseif fieldType == FIELD_TYPE_BITMASK_INT53 then 
      if isArray then 
         return 'int53[]'
      else
         return 'int53'
      end
   elseif fieldType == FIELD_TYPE_BITMASK_DOUBLE then 
      if isArray then 
         return 'double[]'
      else
         return 'double'
      end
   elseif fieldType == FIELD_TYPE_BITMASK_STRING then 
      if isArray then 
         return 'string[]'
      else
         return 'string'
      end
   elseif fieldType == FIELD_TYPE_BITMASK_SCHEMA then 
      if isArray then 
         return 'ref[]'
      else
         return 'ref'
      end
   else
      return 'unknown'
   end
end

--[[
   Mascara usada para extrair os dados de um byte do header, conforme modelo

   1 1 1 1 1 1 1 1
   |   | | |     |
   |   | | +-----+--- 4 bits para identificar o campo, portanto, um schema pode ter no máximo 16 campos (2^4)
   |   | |            
   |   | +----------- 1 bit  IS ARRAY flag que determina se é array
   +---+------------- 3 bits determina o tipo do dado
]]
local FIELD_BITMASK_FIELD_ID    = 15  -- 00001111
local FIELD_BITMASK_IS_ARRAY    = 16  -- 00010000
local FIELD_BITMASK_FIELD_TYPE  = 224 -- 11100000

-- O byte vazio do header
local HEADER_EMPTY_BYTE = 64 -- 1000000 (64 @)

-- os 6 LSB 
local HEADER_BITMASK_INDEX = {
   32, -- 100000
   16, -- 010000
   8,  -- 001000
   4,  -- 000100
   2,  -- 000010
   1   -- 000001
}

-- local Lib = game.ReplicatedStorage:WaitForChild("Lib")
-- require(game.ReplicatedStorage:WaitForChild("Lib"):WaitForChild("Promise"))

-- verifica se precisa incrementar o header para o proximo byte
-- 
-- O header é usado para determinar o range do byte sendo trabalhado. 
-- Durante o encode, quando o byte é: 
--    < 92            Salva as is e mapeia o bit 0 no header
--    > 92 e < 184    Subtrai 92 para mapear e mapeia o bit atual como 1 e o seguinte como 0
--    > 184           Subtrai 184 para mapear e mapeia o bit atual e o seguinte como 1
-- Durante o decode, verifica no header como o byte atual está salvo, permitindo descobrir o valor correto do byte
-- usa 6 LSB de 1000000 (64 @) até 1111111 (127 DEL), porém, ao persistir, substitui 
--    A) 01011100 (92  \)   por 00111110 (62 >)
--    B) 11111111 (127 DEL) por 00111111 (63 ?)
-- ao reverter, faz a substituição inversa
local function header_increment(header)
   if header.index > 6 then
      -- 01011100 (92  \) -> 00111110 (62 >)
      if header.byte == 92  then 
         header.byte = 62
      end 

      -- 11111111 (127 DEL) -> 00111111 (63 ?)
      if header.byte == 127 then 
         header.byte = 63
      end 

      header.content[#header.content + 1] = string.char(header.byte)

      header.byte = HEADER_EMPTY_BYTE
      header.index = 1
   end
end

-- O marcador do fim cabeçalho (00111101, 61, =)
local HEADER_END_MARK = '='

-- garante que o header está fechado. Este método só deve ser invocado no último passo do processo de serialização
local function header_flush(header)
   if header.index > 1 then
      header.index = 7
      header_increment(header)
   end

   -- adiciona o marcador do fim cabeçalho
   header.content[#header.content + 1] = HEADER_END_MARK
   header.content = table.concat(header.content, '')
end

--[[
   Faz o encode de um byte (inteiro entre 0 e 255) para o seu correlacionado em ASCII válido a referencia do header 
   é necessário para garantir a deserialização do item

   @header  {Object}    Referencia para o header da serialização
   @byte    {int8}      O byte que será transformado para a sua referencia como char

   @return {char}
]]
local function encode_byte(header, byte)
   local out
   if byte < 92 then
      out = CHARS[byte]
      header.index = header.index + 1

   elseif byte < 184 then
      out = CHARS[byte - 92]

      -- Usa 2 bits no header, no formato 10

      -- 0001 | 00010 = 0011
      header.byte = bor(header.byte, HEADER_BITMASK_INDEX[header.index])
      header.index = header.index+1
      header_increment(header)
      header.index = header.index+1

   else
      out = CHARS[byte - 184]

      -- Usa 2 bits no header, no formato 11

      -- 0001 | 00010 = 0011
      header.byte = bor(header.byte, HEADER_BITMASK_INDEX[header.index])
      header.index = header.index+1
      header_increment(header)
      header.byte = bor(header.byte, HEADER_BITMASK_INDEX[header.index])
      header.index = header.index+1

   end

   header_increment(header)
   
   return out
end

--[[
   Faz o decode de um char que foi serializado pelo método encode_byte

   @return {int8} 
]]
local function decode_char(header, char)
   local byte = CHARS_BY_KEY[char]
   local shift = header.shift[header.index]
   header.index = header.index + 1

   if shift == 0 then 
      return byte
   elseif shift == 1 then 
      return byte + 92
   else
      return byte + 184
   end
end

--[[

   @TODO: Replicar documentação do Serializer aqui

   @header        {Object} Referencia para o cabeçalho da serialização atual
   @fieldId       {int4}   O id do field sendo serializado
   @fieldTypeMask {int4}   Ver as constantes FIELD_TYPE_MASK_* 
   @isArray       {bool}   É um array de itens sendo serializado?

   @return char
]]
local function encode_field(header, fieldId, fieldType, isArray)
   if fieldId > 16 or fieldId < 0 then 
      error('Unexpected field id '..fieldId)
   end

   local byte = bor(fieldId, fieldType)
   if isArray then
      -- 16 = 00010000
      -- 00000000 | 10000 = 10000
      byte = bor(byte, FIELD_BITMASK_IS_ARRAY)
   end

   return encode_byte(header, byte)
end

--[[
   Ver encode_field

   @byte {int8} O byte gerado no encode_field
]]
local function decode_field_byte(byte)
   return {
      Id       = band(byte, FIELD_BITMASK_FIELD_ID),
      Type     = band(byte, FIELD_BITMASK_FIELD_TYPE),
      IsArray  = band(byte, FIELD_BITMASK_IS_ARRAY) ~= 0
   }
end

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

local INT_EXTRA_BITMASK_NEGATIVE       = 128 -- 10000000
local INT_EXTRA_BITMASK_IT_FITS        = 64  -- 01000000
local INT_EXTRA_BITMASK_VALUE          = 63  -- 00111111
local INT53_EXTRA_BITMASK_IS_BIG       = 32  -- 00100000
local INT53_EXTRA_BITMASK_HAS_MORE     = 16  -- 00010000
local INT_EXTRA_BITMASK_BYTE_COUNT     = 12  -- 00001100
local INT53_EXTRA_BITMASK_BYTE_COUNT   = 3   -- 00000011

-- quantos bytes [chars] é usado pelo int32 na sequencia (4 valores)
-- Usado pelo int53 para determinar o multiplicador
local INT_EXTRA_BITMASK_NUM_BYTES = {
   0,    -- 00000000   = 1 byte
   4,    -- 00000100   = 2 bytes
   8,    -- 00001000   = 3 bytes
   12    -- 00001100   = 4 bytes
}

-- quantos bytes [chars] é usado pelo resto do int53 na sequencia (4 valores)
local INT53_EXTRA_BITMASK_NUM_BYTES = {
   0, -- 00000000   = 1 byte
   1, -- 00000001   = 2 bytes
   2, -- 00000010   = 3 bytes
   3  -- 00000011   = 4 bytes
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
  
   local isNegative = band(byteExtra, INT_EXTRA_BITMASK_NEGATIVE) ~= 0

   if band(byteExtra, INT_EXTRA_BITMASK_IT_FITS) ~= 0 then 
      -- valor cabe nos 4 últimos bits
      local value = band(byteExtra, INT_EXTRA_BITMASK_VALUE)
      if isNegative then 
         value = -1 * value
      end
      return {
         ValueFits   = true,
         Value       = value
      }
   end

   -- has more
   return {
      Bytes       = rshift(band(byteExtra, INT_EXTRA_BITMASK_BYTE_COUNT), 2) + 1,
      ValueFits   = false,
      IsNegative  = isNegative
   }
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

--[[
   Lógica comum aos métodos encode_field_int53 e encode_field_int53_array

   Faz o encode de um int53, no formato <{EXTRA}[{VALUE}]?>

   {EXTRA}
      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | | |
      | | | | | | +-+--- 2 bits  quantos bytes [chars] é usado pelo int32 do resto (4 valores)
      | | | | +-+------- 2 bits  quantos bytes [chars] é usado pelo int32 do multiplicador (4 valores)
      | | | +----------- 1 bits  HAS_MORE? Usado pelo encode_field_int53_array para indicar continuidade
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
   
   -- print('value', value, hasMore)
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


      print('times', times, 'rest', rest)

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
local function encode_field_int53(header, field, value)

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
   Faz a decodifiação do EXTRA de um int53, ver `encode_field_int53(header, fieldId, value)`

   @byteExtra  {int8} O {EXTRA} byte que foi gerado pelo método `encode_field_int53(header, fieldId, value)`

   @return {object} informações contidas no {EXTRA}
]]
local function decode_int53_extra_byte(byteExtra)
  
   return {
      IsNegative  = band(byteExtra, INT_EXTRA_BITMASK_NEGATIVE) ~= 0,
      IsBig       = band(byteExtra, INT53_EXTRA_BITMASK_IS_BIG)  ~= 0,
      HasMore     = band(byteExtra, INT53_EXTRA_BITMASK_HAS_MORE) ~= 0,
      BytesTimes  = rshift(band(byteExtra, INT_EXTRA_BITMASK_BYTE_COUNT), 2) + 1,
      BytesRest   = band(byteExtra, INT53_EXTRA_BITMASK_BYTE_COUNT) + 1,
   }
end

--[[
   Faz a decodifiação dos bytes que compoem um int53, apenas quando é BIG, ver função `encode_field_int53(header, fieldId, value)` 

   @bytes      {int8[]} O bytes que foram gerados pelo método `encode_field_int53(header, fieldId, value)`
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

   local out = {
      Items = {
         {
            Bytes       = rshift(band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_BYTE_COUNT[1][1]), INT32_ARRAY_EXTRA_BITMASK_BYTE_COUNT[1][2]) + 1,
            IsNegative  = band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NEGATIVE[1]) ~= 0,
            HasMore     = band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_HAS_MORE[1]) ~= 0
         }
      }
   }
  
   -- has more
   if out.Items[1].HasMore then 
      table.insert(out.Items, {
         Bytes       = rshift(band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_BYTE_COUNT[2][1]), INT32_ARRAY_EXTRA_BITMASK_BYTE_COUNT[2][2]) + 1,
         IsNegative  = band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_NEGATIVE[2]) ~= 0,
         HasMore     = band(byteExtra, INT32_ARRAY_EXTRA_BITMASK_HAS_MORE[2]) ~= 0
      })
   end

   return out
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
local function encode_field_int53_array(header, field, values)
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

--[[
   Faz o ecode de um field do tipo schema, no seguinte formato <{FIELD_REF}{SCHEMA_ID}[{VALUE}]{FIELD_REF_END}>

   Onde:

   FIELD_REF      = FIELD_TYPE_BITMASK_SCHEMA, com IS_ARRAY=false
   SCHEMA_ID      = byte
   [{VALUE}]      = Conteúdo do shema serializado
   FIELD_REF_END  = FIELD_TYPE_BITMASK_SCHEMA_END, marca o fim desse objeto

   @header  {Object} Referencia para o header
   @field   {Object} A referencia para o campo
   @value   {Object} O objeto que será serializado
]]
local function encode_field_schema(header, field, value)
   if value == nil or field.Schema == nil then 
      return ''
   end

   return table.concat({
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_SCHEMA, false),
      serialize(value, field.Schema, false)
   }, '')
end

--[[
   Faz o ecode de um field do tipo array de schema, no seguinte formato <{FIELD_REF}{SCHEMA_ID}[<[{VALUE}]{FIELD_REF_END}>]>

   Onde:

   FIELD_REF                     = FIELD_TYPE_BITMASK_SCHEMA, com IS_ARRAY=true
   SCHEMA_ID                     = byte
   [<[{VALUE}]{FIELD_REF_END}>]  = Array de conteúdo de cada schema sendo serializado
                                    FIELD_REF_END  = FIELD_TYPE_BITMASK_SCHEMA_END, marca o fim de um item, usa o 
                                    byte IS_ARRAY para indicar se possui mais registros na sequencia

   @header  {Object} Referencia para o header
   @field   {Object} A referencia para o campo
   @value   {Object} O objeto que será serializado
]]
local function encode_field_schema_array(header, field, values)
   local schema = field.Schema
   if values == nil or schema == nil or table.getn(values) == 0 then 
      return ''
   end

   local len = #values

   local out = {
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_SCHEMA, true)
   }

   for i, value in ipairs(values) do
      out[#out + 1] = serialize(value, schema, i ~= len)
   end

   return table.concat(out, '')
end

--[[
   Utilitário para setar o valor de um campo de um objeto durante a deserialização
]]
local function set_object_value(objectCurrent, value, schema, fieldDecoded)
   if schema ~= nil then 
      local field = schema.FieldsById[fieldDecoded.Id]
      if field ~= nil then
         if field.Type == fieldDecoded.Type and field.IsArray == fieldDecoded.IsArray then 
            objectCurrent[field.Name] = value
         else
            print(table.concat({
               'WARNING: Deserialize - O tipo do campo é diferente do valor serializado (',
               'SCHEMA_ID=', schema.Id, ', ',
               'FIELD_ID=', field.Id, ', ',
               'FIELD_NAME=', field.Name, ', ',
               'FIELD_TYPE=', get_field_type_name(field.Type, field.IsArray), ', ',
               'CONTENT_FIELD_TYPE=', get_field_type_name(fieldDecoded.Type, fieldDecoded.IsArray),
               ')'
            }, ''))
         end
      end
   end
end

--[[
   Faz a serialização de um registro

   Uma mensagem serializada tem a seguinte estrutura {HEADER}{SCHEMA_ID}[<{FIELD}[<{EXTRA}?[{VALUE}]?>]>], Onde:

   
   HEADER {bit variable} 
      O header abriga a informação sobre o deslocamento dos bytes serializados. O deslocamento é necessário para que 
      os bytes encodados permaneçam no range dos 92 caracteres usados  

   SCHEMA_ID {8 bits}   
      É o id do esquema da mensagem, o sistema permite a criação de até 255 esquemas distintos
   
   FIELD {8 bits} 
      É a definição da chave do campo do esquema
      Quando uma mensagem é codificada, as chaves e os valores são concatenados. Quando a mensagem está sendo 
      decodificada, o analisador precisa ser capaz de pular os campos que não reconhece. Desta forma, novos campos 
      podem ser adicionados a uma mensagem sem quebrar programas antigos que não os conhecem. Para esse fim, a "chave" 
      para cada par em uma mensagem em formato de ligação é, na verdade, dois valores - o identificador do campo no 
      schema, mais um tipo de ligação que fornece informações suficientes para encontrar o comprimento do valor a seguir.

      1 1 1 1 1 1 1 1
      |   | | |     |
      |   | | +-----+--- 4 bits  para identificar o campo, portanto, um schema pode ter no máximo 16 campos (2^4)
      |   | |            
      |   | +----------- 1 bit   IS ARRAY flag que determina se é array
      |   |                         Exceção FIELD_TYPE_BITMASK_BOOL, que usa esse bit para guardar o valor
      |   |
      +---+------------- 3 bits  determina o FIELD_TYPE

         FIELD_TYPE
            |     mask    |    type    |       constant                |
            | ----------- | ---------- | ------------------------------| 
            | 0 0 0 00000 | bool       | FIELD_TYPE_BITMASK_BOOL       |
            | 0 0 1 00000 | bool[]     | FIELD_TYPE_BITMASK_BOOL_ARRAY |
            | 0 1 0 00000 | int32      | FIELD_TYPE_BITMASK_INT32      |
            | 0 1 1 00000 | int53      | FIELD_TYPE_BITMASK_INT53      |
            | 1 0 0 00000 | double     | FIELD_TYPE_BITMASK_DOUBLE     |
            | 1 0 1 00000 | string     | FIELD_TYPE_BITMASK_STRING     |
            | 1 1 0 00000 | ref        | FIELD_TYPE_BITMASK_SCHEMA     |
            | 1 1 1 00000 | ref end    | FIELD_TYPE_BITMASK_SCHEMA_END |

   <{EXTRA}?[{VALUE}]?> - EXTRA {8 bits}, VALUE {bit variable}
      Definições adicionais à respeito do conteúdo, depende da informação contida na FIELD

      - bool
         Não se aplica, valor já é salvo junto com FIELD

      - bool[]
         Não possui {EXTRA}
         Encoda o array de booleanos no [{VALUE}] (ver `encode_field_bool_array(header, fieldId, value)`)

      - int32
         Formato <{EXTRA}[{VALUE}]?>, ver `encode_field_int32(header, fieldId, value)`

      - int32[]
         Repete a estrutura <{EXTRA}[{VALUE}]> até que o LSB do EXTRA seja 0, ver `encode_field_int32_array(header, fieldId, value)`

      - int32
         Formato <{EXTRA}[{VALUE}]?>, ver `encode_field_int53(header, fieldId, value)`

      - ref
         Possui a seguinte estrutura <{FIELD_REF}{SCHEMA_ID}[{VALUE}]{FIELD_REF_END}>, ver `encode_field_schema(header, field, value)`
      
      - ref[]
         Possui a seguinte estrutura <{FIELD_REF}{SCHEMA_ID}[<[{VALUE}]{FIELD_REF_END}>]>, ver `encode_field_schema_array(header, field, value)`

         

   VALUE {bit variable} 
      É o próprio conteúdo


   @data    {object} Os dados que serão serialzizados
   @schema  {Schema} Referencia para o schema
   @hasMore {bool}   O marcador de final de schema FIELD_TYPE_BITMASK_SCHEMA_END usa o IS_ARRAY para informar se existe 
                        outro objeto serializado na sequencia, usado quando é um array de Schema

   @return string
]]
serialize = function(data, schema, hasMore)
   if data == nil then 
      print('WARNING: serialize - Recebeu nil como entrada, ignorando serialização (Name='..schema.Name..')')
      return ''
   end

   local header = { index = 1, byte = HEADER_EMPTY_BYTE, content = {}}
   
   local out = {
      '',                             -- {HEADER} (substituido no final da execução)
      encode_byte(header, schema.Id)  -- {SCHEMA_ID}
   }

   local value, content
   for _, field in ipairs(schema.Fields) do
      value = data[field.Name]
      if value ~= nil then
         -- <{FIELD}{EXTRA?}{VALUE?}...>
         content = field.EncodeFn(header, field, value)
         if content ~= '' then
            out[#out + 1] = content
         end
      end
   end

   -- usa IS_ARRAY para informar se possui mais itens
   out[#out + 1] = encode_field(header, 0, FIELD_TYPE_BITMASK_SCHEMA_END, hasMore)

   if #out == 2 then
      -- data is empty (only {HEADER} and {SCHEMA_ID})
      return ''
   end

   header_flush(header)
   out[1] = header.content
   return table.concat(out, '')
end

--[[
   Faz a De-serialização de um conteúdo.

   É permitido que existam vários registros serializados concatenados no conteúdo, o sistema por padrão irá retonar 
   apenas o primeiro registro.
   
   Se desejar que seja retornado um array com todos os registros existentes, basta informar `true` o parametro `all`,
   desse modo o método sempre retornará um array

   @content    {string}    Conteúdo serializado
   @all        {bool}      Permite retornar todos os registros que estão concatenados neste conteúdo 

   @return {Object|Array<Object>} se `all` = `true` retorna array com todos os registros concatenados no conteúdo
]]
local function deserialize(content, all)

   local header            = { shift = {}, index = 1} -- os dados do cabeçalho que foi deserializado
   local fieldDecoded      = nil    -- dados brutos do field, obtido da função `decode_field(header, char)`
   local inHeader          = true   -- está processando o header?
   local inHeaderBit2      = false  -- o header identifica o shift de um byte, ver a função `encode_byte`
   local schemaId          = nil    -- O id do schema sendo processado, logo após o {HEADER}
   local schema            = nil    -- A referencia para o Schema sendo processado
   local inString          = false  -- está processando uma string (UTF-8)
   local inExtraByte       = false  -- está processando o extra
   local inValue           = false  -- está processando um valor (após descobir o field)
   local extraByteDecoded  = false  -- dados do extra-field processado
   local isCaptureBytes    = false  -- está guardando bytes
   local captureBytesCount = 0      -- quantos bytes seguintes é para guardar
   local capturedBytes     = {}     -- os bytes
   local stringCount       = 0 
   local stringValue       = nil
   local value             = nil    -- a referencia para o valor do campo atual
   local object            = {}    -- gerenciamento da estrutura do objeto
   
   local stack = {}
   
   local i                 = 0      -- auxiliar, apenas para identificar a posição caso exista inconsistencia
   for char in content:gmatch(utf8.charpattern) do
      i = i+1

      if inHeader then
         if char == HEADER_END_MARK then 
            inHeader = false

         else
            local byte = string.byte(char)
            --  00111110 (62 >) -> 01011100 (92  \)
            if byte == 62  then 
               byte = 92
            end 
   
            -- 00111111 (63 ?) -> 11111111 (127 DEL)
            if byte == 63 then 
               byte = 127
            end 
   
            if byte > 127 or byte < 64 then 
               error('Unexpected value ('..char..') in the header at position '..i)
            end
   
            for _, mask in ipairs(HEADER_BITMASK_INDEX) do
               -- 01000101 & 000001
               if band(byte, mask) == 0 then
                  if inHeaderBit2 then 
                     -- byte maior que 92 e menor que 184
                     table.insert(header.shift, 1)
                     inHeaderBit2 = false
                  else
                     -- byte menor que 92 
                     table.insert(header.shift, 0)
                  end
               else 
                  if inHeaderBit2 then  
                     -- byte maior que 184
                     table.insert(header.shift, 2)
                     inHeaderBit2 = false
                  else
                     inHeaderBit2 = true
                  end
               end
            end
         end
      elseif schemaId == nil then
         schemaId = decode_char(header, char)
         schema   = SCHEMA_BY_ID[schemaId]

         -- verifica se o schema está registrado
         if schema == nil and all ~= true then 
            print('WARNING: Deserialize - O conteúdo faz referência para um schema não cadastrado (SCHEMA_ID='..schemaId..')')
            return nil
         end

      elseif inExtraByte then
         -- extra byte

         inExtraByte = false
         local extraByte = decode_char(header, char)

         if fieldDecoded.Type == FIELD_TYPE_BITMASK_INT32 then

            if fieldDecoded.IsArray then 
               extraByteDecoded = decode_int32_array_extra_byte(extraByte)
               -- Bytes
               if value == nil then 
                  value = {}
               end
               isCaptureBytes    = true
               capturedBytes     = {}
               captureBytesCount = extraByteDecoded.Items[1].Bytes
               extraByteDecoded.Index = 1

            else 
               extraByteDecoded = decode_int32_extra_byte(extraByte)
               if extraByteDecoded.ValueFits then
                  -- Inteiro menor que 64, coube no EXTRA_BYTE 
                  set_object_value(object, extraByteDecoded.Value, schema, fieldDecoded)
                  value = nil
                  extraByteDecoded = nil
               else
                  -- Bytes
                  isCaptureBytes    = true
                  capturedBytes     = {}
                  captureBytesCount = extraByteDecoded.Bytes
               end
            end 
         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_INT53 then

            extraByteDecoded = decode_int53_extra_byte(extraByte)
            -- Bytes
            isCaptureBytes    = true
            capturedBytes     = {}

            if extraByteDecoded.IsBig then 
               captureBytesCount = extraByteDecoded.BytesTimes + extraByteDecoded.BytesRest
            else
               captureBytesCount = extraByteDecoded.BytesTimes
            end

            if fieldDecoded.IsArray then
               -- Bytes
               if value == nil then 
                  value = {}
               end      
            end
         end

      elseif isCaptureBytes then
         capturedBytes[#capturedBytes + 1] = decode_char(header, char)
         captureBytesCount = captureBytesCount - 1

         if captureBytesCount == 0 then 
            isCaptureBytes = false

            if fieldDecoded.Type == FIELD_TYPE_BITMASK_INT32 then

               if fieldDecoded.IsArray then
                  value[#value + 1] = decode_int32_bytes(capturedBytes, extraByteDecoded.Items[extraByteDecoded.Index].IsNegative)

                  if extraByteDecoded.Items[extraByteDecoded.Index].HasMore then
                     extraByteDecoded.Index  = extraByteDecoded.Index + 1
                     if extraByteDecoded.Index > 2 then 
                        -- somente 2 int32 por extra
                        inExtraByte = true
                     else
                        -- captura bytes do proximo int32 na sequencia
                        isCaptureBytes    = true
                        capturedBytes     = {}
                        captureBytesCount = extraByteDecoded.Items[2].Bytes
                     end
                  else
                     set_object_value(object, value, schema, fieldDecoded)
                     value = nil
                  end 
               else                  
                  value = decode_int32_bytes(capturedBytes, extraByteDecoded.IsNegative)
                  set_object_value(object, value, schema, fieldDecoded)
                  value = nil
               end

            elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_INT53 then
               if fieldDecoded.IsArray then
                  if extraByteDecoded.IsBig then 
                     value[#value + 1] = decode_int53_bytes(
                        capturedBytes, 
                        extraByteDecoded.IsNegative, 
                        extraByteDecoded.BytesTimes,
                        extraByteDecoded.BytesRest
                     )
                  else
                     value[#value + 1] = decode_int32_bytes(capturedBytes, extraByteDecoded.IsNegative)
                  end 

                  if extraByteDecoded.HasMore then
                     inExtraByte = true
                  else
                     set_object_value(object, value, schema, fieldDecoded)
                     value = nil
                  end
               else
                  if extraByteDecoded.IsBig then 
                     value = decode_int53_bytes(
                        capturedBytes, 
                        extraByteDecoded.IsNegative, 
                        extraByteDecoded.BytesTimes,
                        extraByteDecoded.BytesRest
                     )
                  else
                     value = decode_int32_bytes(capturedBytes, extraByteDecoded.IsNegative)
                  end 
                  set_object_value(object, value, schema, fieldDecoded)
                  value = nil
               end
            end
         end

      -- @TODO: Remover esse fluxo
      elseif inValue then 
         if inString then

         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_BOOL_ARRAY then
            if not decode_bool_array_byte(decode_char(header, char), value) then               
               inValue  = false -- bool array não possui mais dados
            end
         end
         
         -- se o schema não existir, ignora parse dos dados
         if not inValue and schema ~= nil then 
            -- @TODO: Após o processamento do dado bruto, invoca o decode do campo

            set_object_value(object, value, schema, fieldDecoded)
            value          = nil
            fieldDecoded   = nil
         end
      else 
         -- in field
         fieldDecoded = decode_field_byte(decode_char(header, char))
         inExtraByte = true

         if fieldDecoded.Type == FIELD_TYPE_BITMASK_BOOL then
            -- o tipo bool salva o valor no mesmo byte do field
            value = fieldDecoded.IsArray
            fieldDecoded.IsArray = false
            set_object_value(object, value, schema, fieldDecoded)            
            value       = nil 
            inExtraByte = false  -- não possui extra byte

         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_BOOL_ARRAY then
            value       = {}
            inValue     = true   
            inExtraByte = false  -- não possui extra byte

         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_SCHEMA then

            inExtraByte = false  -- não possui extra byte

            if fieldDecoded.IsArray then 
               value = {}
            else
               value = nil
            end

            -- salva o estado atual
            table.insert(stack, {
               header            = header,
               fieldDecoded      = fieldDecoded,
               inHeader          = inHeader,
               inHeaderBit2      = inHeaderBit2,
               schemaId          = schemaId,
               schema            = schema,
               inString          = inString,
               inExtraByte       = inExtraByte,
               inValue           = inValue,
               extraByteDecoded  = extraByteDecoded,
               isCaptureBytes    = isCaptureBytes,
               captureBytesCount = captureBytesCount,
               capturedBytes     = capturedBytes,
               stringCount       = stringCount,
               stringValue       = stringValue,
               value             = value,
               object            = object,
            })

            -- faz o reset das variáveis
            header            = { shift = {}, index = 1}
            fieldDecoded      = nil
            inHeader          = true
            inHeaderBit2      = false
            schemaId          = nil
            schema            = nil
            inString          = false
            inExtraByte       = false
            inValue           = false
            extraByteDecoded  = false
            isCaptureBytes    = false
            captureBytesCount = 0
            capturedBytes     = {}
            stringCount       = 0
            stringValue       = nil
            value             = nil 
            object            = {}

         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_SCHEMA_END then

            inExtraByte = false  -- não possui extra byte

            local parent = stack[#stack]

            if parent ~= nil then 
               if parent.fieldDecoded.IsArray then
                  table.insert(parent.value, object)
   
                  local hasMore = fieldDecoded.IsArray
                  if hasMore then 
                     -- faz o reset das variáveis
                     header            = { shift = {}, index = 1}
                     fieldDecoded      = nil
                     inHeader          = true
                     inHeaderBit2      = false
                     schemaId          = nil
                     schema            = nil
                     inString          = false
                     inExtraByte       = false
                     inValue           = false
                     extraByteDecoded  = false
                     isCaptureBytes    = false
                     captureBytesCount = 0
                     capturedBytes     = {}
                     stringCount       = 0
                     stringValue       = nil
                     value             = nil 
                     object            = {}
                  else 
                     -- faz o reset das variáveis do parent
                     header            = parent.header
                     fieldDecoded      = parent.fieldDecoded
                     inHeader          = parent.inHeader
                     inHeaderBit2      = parent.inHeaderBit2
                     schemaId          = parent.schemaId
                     schema            = parent.schema
                     inString          = parent.inString
                     inExtraByte       = parent.inExtraByte
                     inValue           = parent.inValue
                     extraByteDecoded  = parent.extraByteDecoded
                     isCaptureBytes    = parent.isCaptureBytes
                     captureBytesCount = parent.captureBytesCount
                     capturedBytes     = parent.capturedBytes
                     stringCount       = parent.stringCount
                     stringValue       = parent.stringValue
                     value             = parent.value
                     object            = parent.object
   
                     table.remove(stack, #stack)
                     set_object_value(object, value, schema, fieldDecoded)
                     value = nil
                  end 
               else
                  table.remove(stack, #stack)
                  set_object_value(parent.object, object, parent.schema, parent.fieldDecoded)

                  -- faz o reset das variáveis
                  header            = parent.header
                  fieldDecoded      = parent.fieldDecoded
                  inHeader          = parent.inHeader
                  inHeaderBit2      = parent.inHeaderBit2
                  schemaId          = parent.schemaId
                  schema            = parent.schema
                  inString          = parent.inString
                  inExtraByte       = parent.inExtraByte
                  inValue           = parent.inValue
                  extraByteDecoded  = parent.extraByteDecoded
                  isCaptureBytes    = parent.isCaptureBytes
                  captureBytesCount = parent.captureBytesCount
                  capturedBytes     = parent.capturedBytes
                  stringCount       = parent.stringCount
                  stringValue       = parent.stringValue
                  value             = parent.value
                  object            = parent.object
               end
            end
         end
      end
   end

   return object
end

local Schema = {}
Schema.__index = Schema

--[[
   Permite adicionar um campo no Schema
]]
function Schema:Field(id, name, fieldType, isArray, maxLength)
   
   if id == nil or type(id) ~= 'number' or math.floor(id) ~= id or id < 0 or id > 16 then
      error('O Id do campo deve ser um número inteiro entre 0 e 16')
   end
      
   if name == nil or  type(name) ~= 'string' or name == '' then
      error('O Nome do campo deve ser uma string válida')
   end

   if fieldType == nil then 
      error('O Tipoo de dado do campo é requerido')
   end

   for _, field in ipairs(self.Fields) do
      if field.Name == name then 
         error('Já existe um campo registrado com o mesmo nome '..name)
      end

      if field.Id == id then 
         error('Já existe um campo registrado com o mesmo id '..id)
      end
   end

   local field = {}
   field.Id       = id
   field.Name     = name
   field.IsArray  = isArray == true

   if fieldType == 'int32' then 
      field.Type = FIELD_TYPE_BITMASK_INT32
      if field.IsArray then 
         field.EncodeFn = encode_field_int32_array
      else
         field.EncodeFn = encode_field_int32
      end
      
   elseif fieldType == 'int53' then 
      field.Type = FIELD_TYPE_BITMASK_INT53
      if field.IsArray then 
         field.EncodeFn = encode_field_int53_array
      else
         field.EncodeFn = encode_field_int53
      end

   elseif fieldType == 'double' then 
      field.Type = FIELD_TYPE_BITMASK_DOUBLE

   elseif fieldType == 'bool' then
      
      if field.IsArray then 
         field.Type     = FIELD_TYPE_BITMASK_BOOL_ARRAY
         field.EncodeFn = encode_field_bool_array
         
      else
         field.Type = FIELD_TYPE_BITMASK_BOOL
         field.EncodeFn = encode_field_bool
         
      end
      
   elseif fieldType == 'string' then 
      field.Type = FIELD_TYPE_BITMASK_STRING
      if maxLength ~=nil and type(maxLength) == 'number' then
         field.MaxLength = math.floor(maxLength)
         if field.MaxLength <= 0 then
            field.MaxLength = nil
         end 
      end
      
   elseif fieldType.isSchema then 
      -- schema ref
      field.Type     = FIELD_TYPE_BITMASK_SCHEMA
      field.Schema   = fieldType
      
      if field.IsArray then  
         field.EncodeFn = encode_field_schema_array
      else
         field.EncodeFn = encode_field_schema
      end

   else 
      -- @TODO: Verificar se é referencia para Vector3 ou outros fields padrões
      
   end 

   table.insert(self.Fields, field)
   self.FieldsById[field.Id] = field

   return self
end

--[[
   Permite definir uma função que será usada para transformar o objeto bruto em um objeto serializável
]]
function Schema:Encoder(func)
   if type(func) ~= 'function' then
      error('O método Encoder uma função como parametro de entrada')
   end
   self.EncoderFn = func

  return self
end

--[[
   Permite definir uma função que será usada para transformar um objeto em sua instancia final
]]
function Schema:Decoder(func)
   if type(func) ~= 'function' then
      error('O método Decoder uma função como parametro de entrada')
   end
   self.DecoderFn = func

   return self
end


function Schema:Serialize(data)
   return serialize(data, self, false)
end

--[[
   Registra um novo schema

   Params
      id       {int8}   o identificador do schema
      fields   {Field}  Os campos
]]
local function CreateSchema(id)

   if type(id) == 'number' then
      if id < 0  or id > 220 then
         -- sistema reserva 35 ids para uso interno, para permitir uso de Vector3 e outras instancias comuns
         error('O id do eschema deve ser >= 0 e <= 220')
      end
         
      if SCHEMA_BY_ID[id] ~= nil then
         error('Já existe um schema registrado com o Id informado')
      end
   
      local schema = {}
      schema.isSchema   = true
      schema.Id         = id
      schema.Fields     = {}
      schema.FieldsById = {}
      setmetatable(schema, Schema)
   
      SCHEMA_BY_ID[id] = schema
   
      return schema
   else
      -- config constructor
      local config = id
      local schema = CreateSchema(config.Id)
      
   end
end

return {
   Create = CreateSchema, 
   Deserialize = deserialize
}
