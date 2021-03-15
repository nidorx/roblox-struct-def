local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

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

local Module = {}
Module.get_field_type_name              = get_field_type_name
Module.header_increment                 = header_increment
Module.header_flush                     = header_flush
Module.encode_byte                      = encode_byte
Module.decode_char                      = decode_char
Module.encode_field                     = encode_field
Module.decode_field_byte                = decode_field_byte
Module.FIELD_TYPE_BITMASK_BOOL          = FIELD_TYPE_BITMASK_BOOL
Module.FIELD_TYPE_BITMASK_BOOL_ARRAY    = FIELD_TYPE_BITMASK_BOOL_ARRAY
Module.FIELD_TYPE_BITMASK_INT32         = FIELD_TYPE_BITMASK_INT32
Module.FIELD_TYPE_BITMASK_INT53         = FIELD_TYPE_BITMASK_INT53
Module.FIELD_TYPE_BITMASK_DOUBLE        = FIELD_TYPE_BITMASK_DOUBLE
Module.FIELD_TYPE_BITMASK_STRING        = FIELD_TYPE_BITMASK_STRING
Module.FIELD_TYPE_BITMASK_SCHEMA        = FIELD_TYPE_BITMASK_SCHEMA
Module.FIELD_TYPE_BITMASK_SCHEMA_END    = FIELD_TYPE_BITMASK_SCHEMA_END
Module.HEADER_EMPTY_BYTE                = HEADER_EMPTY_BYTE
Module.HEADER_BITMASK_INDEX             = HEADER_BITMASK_INDEX
Module.HEADER_END_MARK                  = HEADER_END_MARK
return Module
