local bor, band, rshift, lshift = bit32.bor, bit32.band, bit32.rshift, bit32.lshift

-- the characters used to encode the numeric values and markers of the objects
local CHARS = {
   "#","$","%","&","'","(",")","*","+",",","-",".","/",
   "0","1","2","3","4","5","6","7","8","9",":",";","<",
   "=",">","?","@","A","B","C","D","E","F","G","H","I",
   "J","K","L","M","N","O","P","Q","R","S","T","U","V",
   "W","X","Y","Z","[","]","^","_","`","a","b","c","d",
   "e","f","g","h","i","j","k","l","m","n","o","p","q",
   "r","s","t","u","v","w","x","y","z","{","|","}","~"
}
CHARS[0] = '!' -- lua index starts at 1

-- reverse index, used to perform the decode
local CHARS_BY_KEY = {}
for i =0, table.getn(CHARS) do
   CHARS_BY_KEY[CHARS[i]] = i
end

-- The schema end marker (for nested schemas) (00111100 = 60 = <)
local HEADER_END_MARK = '<'

-- the types of fields available (BITMASK)
local FIELD_TYPE_BITMASK_BOOL        = 0   -- 00000000
local FIELD_TYPE_BITMASK_BOOL_ARRAY  = 32  -- 00100000
local FIELD_TYPE_BITMASK_INT32       = 64  -- 01000000
local FIELD_TYPE_BITMASK_INT53       = 96  -- 01100000
local FIELD_TYPE_BITMASK_DOUBLE      = 128 -- 10000000
local FIELD_TYPE_BITMASK_STRING      = 160 -- 10100000
local FIELD_TYPE_BITMASK_SCHEMA      = 192 -- 11000000
local FIELD_TYPE_BITMASK_SCHEMA_END  = 224 -- 11100000 - Marca o fim de um schema

--[[
   Bit mask used to extract data from a header byte, according to the model

   1 1 1 1 1 1 1 1
      |   | | |     |
      |   | | +-----+--- 4 bits  The field id, therefore, a schema can have a maximum of 16 ((2^4)-1) fields (0 to 15) 
      |   | |            
      |   | +----------- 1 bit   IS_ARRAY flag that determines whether the item is an array
      |   |                         Exception FIELD_TYPE_BITMASK_BOOL, which uses this bit to store the value
      |   |
      +---+------------- 3 bits  determines the FIELD_TYPE
]]
local FIELD_BITMASK_FIELD_ID    = 15  -- 00001111
local FIELD_BITMASK_IS_ARRAY    = 16  -- 00010000
local FIELD_BITMASK_FIELD_TYPE  = 224 -- 11100000

-- The empty byte of the header
local HEADER_EMPTY_BYTE = 64 -- 1000000 (64 @)

-- The header end marker (00111101, 61, =)
local HEADER_END_MARK = '='

-- the 6 LSB
local HEADER_BITMASK_INDEX = {
   32, -- 100000
   16, -- 010000
   8,  -- 001000
   4,  -- 000100
   2,  -- 000010
   1   -- 000001
}

--[[
   For debugging and logs only, gets the field name from the type
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
   check if you need to increment the header for the next byte
   
   The header is used to determine the range of the byte being worked on.

   During encode, when the byte is:
      < 92            Saves the is and maps bit 0 in the header
      > 92 e < 184    Subtracts 92 to map and maps the current bit to 1 and the next one to 0
      > 184           Subtracts 184 to map and maps the current bit and the next one as 1

   During the decode, it checks in the header how the current byte is saved, allowing to find the correct value of the 
   byte uses 6 LSB of 1000000 (64 @) until 1111111 (127 DEL). However, when it persists, it replaces
      A) 01011100 (92  \)   for 00111110 (62 >)
      B) 11111111 (127 DEL) for 00111111 (63 ?)
   when deserializing, it makes the inverse substitution
]]
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


-- ensures that the header is closed. This method should only be invoked in the last step of the serialization process.
local function header_flush(header)
   if header.index > 1 then
      header.index = 7
      header_increment(header)
   end

   -- adds the header end marker
   header.content[#header.content + 1] = HEADER_END_MARK
   header.content = table.concat(header.content, '')
end

--[[
   Encode a byte (integer between 0 and 255) for its correlated in valid ASCII the header reference is necessary to 
   guarantee the item deserialization

   @header  {Object} Reference to the serialization header
   @byte    {byte}   The byte that will be transformed for your reference as char

   @return {char}
]]
local function encode_byte(header, byte)
   local out
   if byte < 92 then
      out = CHARS[byte]
      header.index = header.index + 1

   elseif byte < 184 then
      out = CHARS[byte - 92]

      -- Uses 2 bits in the header, in format 10

      -- 0001 | 00010 = 0011
      header.byte = bor(header.byte, HEADER_BITMASK_INDEX[header.index])
      header.index = header.index+1
      header_increment(header)
      header.index = header.index+1

   else
      out = CHARS[byte - 184]

      -- Uses 2 bits in the header, in format 11

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
   Decodes a char that has been serialized by the encode_byte method

   @return {byte} 
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
   FIELD {1 byte} 
      It is the definition of the schema field key
      When a message is encoded, the keys and values are concatenated. When the message is being decoded, the analyzer 
      must be able to skip fields that it does not recognize. In this way, new fields can be added to a message 
      without breaking features reached by those who do not know them.

      1 1 1 1 1 1 1 1
      |   | | |     |
      |   | | +-----+--- 4 bits  The field id, therefore, a schema can have a maximum of 16 ((2^4)-1) fields (0 to 15) 
      |   | |            
      |   | +----------- 1 bit   IS_ARRAY flag that determines whether the item is an array
      |   |                         Exception FIELD_TYPE_BITMASK_BOOL, which uses this bit to store the value
      |   |
      +---+------------- 3 bits  determines the FIELD_TYPE

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

   @header     {Object} Referencia para o cabeçalho da serialização atual
   @fieldId    {int4}   O Id do field sendo serializado
   @fieldType  {int3}   Ver as constantes FIELD_TYPE_MASK_*
   @isArray    {bool}   É um array de itens sendo serializado?

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
   See `encode_field(header, fieldId, fieldType, isArray)`

   @byte {byte} The byte generated by the function `encode_field (header, fieldId, fieldType, isArray)`
]]
local function decode_field_byte(byte)
   return {
      Id       = band(byte, FIELD_BITMASK_FIELD_ID),
      Type     = band(byte, FIELD_BITMASK_FIELD_TYPE),
      IsArray  = band(byte, FIELD_BITMASK_IS_ARRAY) ~= 0
   }
end

local Core = {}
Core.get_field_type_name              = get_field_type_name
Core.header_increment                 = header_increment
Core.header_flush                     = header_flush
Core.encode_byte                      = encode_byte
Core.decode_char                      = decode_char
Core.encode_field                     = encode_field
Core.decode_field_byte                = decode_field_byte
Core.FIELD_TYPE_BITMASK_BOOL          = FIELD_TYPE_BITMASK_BOOL
Core.FIELD_TYPE_BITMASK_BOOL_ARRAY    = FIELD_TYPE_BITMASK_BOOL_ARRAY
Core.FIELD_TYPE_BITMASK_INT32         = FIELD_TYPE_BITMASK_INT32
Core.FIELD_TYPE_BITMASK_INT53         = FIELD_TYPE_BITMASK_INT53
Core.FIELD_TYPE_BITMASK_DOUBLE        = FIELD_TYPE_BITMASK_DOUBLE
Core.FIELD_TYPE_BITMASK_STRING        = FIELD_TYPE_BITMASK_STRING
Core.FIELD_TYPE_BITMASK_SCHEMA        = FIELD_TYPE_BITMASK_SCHEMA
Core.FIELD_TYPE_BITMASK_SCHEMA_END    = FIELD_TYPE_BITMASK_SCHEMA_END
Core.HEADER_EMPTY_BYTE                = HEADER_EMPTY_BYTE
Core.HEADER_BITMASK_INDEX             = HEADER_BITMASK_INDEX
Core.HEADER_END_MARK                  = HEADER_END_MARK
return Core
