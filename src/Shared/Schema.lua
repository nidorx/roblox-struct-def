--[[
   Roblox Schema v1.0.0 [2021-02-28 22:10]

   Sistema de serialização inspirado no protobuf, com foco em saídas UTF-8

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

local Core = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Core'))
local get_field_type_name              = Core.get_field_type_name
local header_increment                 = Core.header_increment
local header_flush                     = Core.header_flush
local encode_byte                      = Core.encode_byte
local decode_char                      = Core.decode_char
local encode_field                     = Core.encode_field
local decode_field_byte                = Core.decode_field_byte
local FIELD_TYPE_BITMASK_BOOL          = Core.FIELD_TYPE_BITMASK_BOOL
local FIELD_TYPE_BITMASK_BOOL_ARRAY    = Core.FIELD_TYPE_BITMASK_BOOL_ARRAY
local FIELD_TYPE_BITMASK_INT32         = Core.FIELD_TYPE_BITMASK_INT32
local FIELD_TYPE_BITMASK_INT53         = Core.FIELD_TYPE_BITMASK_INT53
local FIELD_TYPE_BITMASK_DOUBLE        = Core.FIELD_TYPE_BITMASK_DOUBLE
local FIELD_TYPE_BITMASK_STRING        = Core.FIELD_TYPE_BITMASK_STRING
local FIELD_TYPE_BITMASK_SCHEMA        = Core.FIELD_TYPE_BITMASK_SCHEMA
local FIELD_TYPE_BITMASK_SCHEMA_END    = Core.FIELD_TYPE_BITMASK_SCHEMA_END
local HEADER_EMPTY_BYTE                = Core.HEADER_EMPTY_BYTE
local HEADER_BITMASK_INDEX             = Core.HEADER_BITMASK_INDEX
local HEADER_END_MARK                  = Core.HEADER_END_MARK

local Bool = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Bool'))
local encode_field_bool       = Bool.encode_field_bool
local encode_field_bool_array = Bool.encode_field_bool_array
local decode_bool_array_byte  = Bool.decode_bool_array_byte

local Int32 = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Int32'))
local encode_field_int32            = Int32.encode_field_int32
local decode_int32_extra_byte       = Int32.decode_int32_extra_byte
local decode_int32_bytes            = Int32.decode_int32_bytes
local encode_field_int32_array      = Int32.encode_field_int32_array
local decode_int32_array_extra_byte = Int32.decode_int32_array_extra_byte

local Int53 = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Int53'))
local encode_field_int53         = Int53.encode_field_int53
local decode_int53_extra_byte    = Int53.decode_int53_extra_byte
local decode_int53_bytes         = Int53.decode_int53_bytes
local encode_field_int53_array   = Int53.encode_field_int53_array

local String = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('String'))
local STRING_MAX_SIZE                  = String.STRING_MAX_SIZE
local encode_string                    = String.encode_string
local decode_string_extra_byte_first   = String.decode_string_extra_byte_first
local decode_string_extra_byte_second  = String.decode_string_extra_byte_second
local encode_string_array              = String.encode_string_array

-- todos os schemas registrados
local SCHEMA_BY_ID = {}

local serialize

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
   local isCaptureBytes    = false  -- está capturando bytes
   local captureCount      = 0      -- quantos itens seguintes é para guardar
   local capturedBytes     = {}     -- os bytes capturados
   local isCaptureChars    = false  -- está capturando chars UTF-8
   local capturedChars     = {}     -- os chars capturados
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
               captureCount = extraByteDecoded.Items[1].Bytes
               extraByteDecoded.Index = 1

            else 
               extraByteDecoded = decode_int32_extra_byte(extraByte)
               if extraByteDecoded.ValueFits then
                  -- Inteiro menor que 64, coube no EXTRA_BYTE 
                  set_object_value(object, extraByteDecoded.Value, schema, fieldDecoded)
                  value             = nil
                  extraByteDecoded  = nil
               else
                  -- Bytes
                  isCaptureBytes    = true
                  capturedBytes     = {}
                  captureCount = extraByteDecoded.Bytes
               end
            end 

         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_INT53 then

            extraByteDecoded = decode_int53_extra_byte(extraByte)
            -- Bytes
            isCaptureBytes    = true
            capturedBytes     = {}

            if extraByteDecoded.IsBig then 
               captureCount = extraByteDecoded.BytesTimes + extraByteDecoded.BytesRest
            else
               captureCount = extraByteDecoded.BytesTimes
            end

            if fieldDecoded.IsArray then
               -- Bytes
               if value == nil then 
                  value = {}
               end      
            end

         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_STRING then
            if fieldDecoded.IsArray and fieldDecoded.Count == nil then
               -- O primeiro EXTRA é a quantidade de itens, ver `encode_string_array(header, field, values)`
               fieldDecoded.Count = extraByte
               value = {}
               -- próximo byte é um extra também
               inExtraByte = true
            else
               if extraByteDecoded == nil then 
                  extraByteDecoded = decode_string_extra_byte_first(extraByte)
   
                  if extraByteDecoded.SizeFits then 
                     isCaptureChars    = true
                     capturedChars     = {}
                     captureCount      = extraByteDecoded.Size

                     if fieldDecoded.IsArray then 
                        fieldDecoded.Count = fieldDecoded.Count - 1
                     end
                  else
                     inExtraByte = true
                  end               
               else
                  extraByteDecoded = decode_string_extra_byte_second(extraByte, extraByteDecoded)
                  isCaptureChars    = true
                  capturedChars     = {}
                  captureCount      = extraByteDecoded.Size
                  if fieldDecoded.IsArray then 
                     fieldDecoded.Count = fieldDecoded.Count - 1
                  end
               end
            end
         end

      elseif isCaptureBytes then
         capturedBytes[#capturedBytes + 1] = decode_char(header, char)
         captureCount = captureCount - 1

         if captureCount == 0 then 
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
                        captureCount = extraByteDecoded.Items[2].Bytes
                     end
                  else
                     set_object_value(object, value, schema, fieldDecoded)
                     value = nil
                     extraByteDecoded = nil
                  end 
               else                  
                  value = decode_int32_bytes(capturedBytes, extraByteDecoded.IsNegative)
                  set_object_value(object, value, schema, fieldDecoded)
                  value = nil
                  extraByteDecoded = nil
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
                     extraByteDecoded = nil
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
                  extraByteDecoded = nil
               end
            end
         end

      elseif isCaptureChars then
         capturedChars[#capturedChars + 1] = char
         captureCount = captureCount - 1
         if captureCount == 0 then 
            isCaptureChars = false

            if fieldDecoded.Type == FIELD_TYPE_BITMASK_STRING then 
               if fieldDecoded.IsArray then 
                  value[#value + 1] = table.concat(capturedChars, '')

                  if fieldDecoded.Count > 0 then
                     -- next string
                     inExtraByte = true
                  else
                     set_object_value(object, value, schema, fieldDecoded)
                     value = nil
                     fieldDecoded = nil
                  end
               else 
                  value = table.concat(capturedChars, '')
                  set_object_value(object, value, schema, fieldDecoded)
                  value = nil
                  fieldDecoded = nil
               end
               extraByteDecoded = nil
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
            value             = nil
            fieldDecoded      = nil
            extraByteDecoded  = nil
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
            local entry = {}
            entry.header            = header
            entry.fieldDecoded      = fieldDecoded
            entry.inHeader          = inHeader
            entry.inHeaderBit2      = inHeaderBit2
            entry.schemaId          = schemaId
            entry.schema            = schema
            entry.inString          = inString
            entry.inExtraByte       = inExtraByte
            entry.inValue           = inValue
            entry.extraByteDecoded  = extraByteDecoded
            entry.isCaptureBytes    = isCaptureBytes
            entry.captureCount = captureCount
            entry.capturedBytes     = capturedBytes
            entry.stringCount       = stringCount
            entry.stringValue       = stringValue
            entry.value             = value
            entry.object            = object
            entry.isCaptureChars    = isCaptureChars
            entry.capturedChars     = capturedChars
            table.insert(stack, entry)

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
            captureCount = 0
            capturedBytes     = {}
            stringCount       = 0
            stringValue       = nil
            value             = nil 
            object            = {}
            isCaptureChars    = false
            capturedChars     = {}

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
                     captureCount      = 0
                     capturedBytes     = {}
                     stringCount       = 0
                     stringValue       = nil
                     value             = nil 
                     object            = {}
                     isCaptureChars    = false
                     capturedChars     = {}
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
                     captureCount      = parent.captureCount
                     capturedBytes     = parent.capturedBytes
                     stringCount       = parent.stringCount
                     stringValue       = parent.stringValue
                     value             = parent.value
                     object            = parent.object
                     isCaptureChars    = parent.isCaptureChars
                     capturedChars     = parent.capturedChars
   
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
                  captureCount      = parent.captureCount
                  capturedBytes     = parent.capturedBytes
                  stringCount       = parent.stringCount
                  stringValue       = parent.stringValue
                  value             = parent.value
                  object            = parent.object
                  isCaptureChars    = parent.isCaptureChars
                  capturedChars     = parent.capturedChars
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
      field.Type        = FIELD_TYPE_BITMASK_STRING
      field.MaxLength   = STRING_MAX_SIZE

      if maxLength ~=nil and type(maxLength) == 'number' then
         field.MaxLength = math.floor(maxLength)
         if field.MaxLength <= 0 then
            field.MaxLength = STRING_MAX_SIZE
         end 
         field.MaxLength = math.min(field.MaxLength, STRING_MAX_SIZE)
      end

      if field.IsArray then  
         field.EncodeFn = encode_string_array
      else
         field.EncodeFn = encode_string
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

local Module = {}
Module.Create        = CreateSchema
Module.Deserialize   = deserialize
return Module
