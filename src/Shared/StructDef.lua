--[[
   Roblox StructDef v1.0.0 [2021-02-28 22:10]

   The Structure Definition, or simply StructDef, is a library that allows the 
   serialization and deserialization of structured data. You define how you want 
   your data to be structured once and then you can use the generated instance 
   to easily write and read your structured data to and from a UTF-8 string.

   https://github.com/nidorx/roblox-struct-def

   Discussions about this script are at https://devforum.roblox.com/t/1112973

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
local encode_bool             = Bool.encode_bool
local encode_bool_array       = Bool.encode_bool_array
local decode_bool_array_byte  = Bool.decode_bool_array_byte

local Int32 = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Int32'))
local encode_int32            = Int32.encode_int32
local decode_int32_extra_byte       = Int32.decode_int32_extra_byte
local decode_int32_bytes            = Int32.decode_int32_bytes
local encode_int32_array      = Int32.encode_int32_array
local decode_int32_array_extra_byte = Int32.decode_int32_array_extra_byte

local Int53 = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Int53'))
local encode_int53            = Int53.encode_int53
local decode_int53_extra_byte = Int53.decode_int53_extra_byte
local decode_int53_bytes      = Int53.decode_int53_bytes
local encode_int53_array      = Int53.encode_int53_array

local Double = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Double'))
local encode_double              = Double.encode_double
local decode_double_extra_byte   = Double.decode_double_extra_byte
local decode_double_bytes        = Double.decode_double_bytes
local encode_double_array        = Double.encode_double_array

local String = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('String'))
local STRING_MAX_SIZE                  = String.STRING_MAX_SIZE
local encode_string                    = String.encode_string
local decode_string_extra_byte_first   = String.decode_string_extra_byte_first
local decode_string_extra_byte_second  = String.decode_string_extra_byte_second
local encode_string_array              = String.encode_string_array

local Converters = require(game.ReplicatedStorage:WaitForChild('Lib'):WaitForChild('Converters'))

-- all registered schemas
local SCHEMA_BY_ID = {}

local serialize

--[[
   Encodes a field of type schema, in the following format <{FIELD_REF}{SCHEMA_ID}[{VALUE}]{SCHEMA_END}>

   Where:

   FIELD_REF      = FIELD_TYPE_BITMASK_SCHEMA, with IS_ARRAY=false
   SCHEMA_ID      = byte
   [{VALUE}]      = Serialized shema content
   SCHEMA_END     = FIELD_TYPE_BITMASK_SCHEMA_END, marks the end of this object

   @header  {Object} Header reference
   @field   {Object} The reference for the field
   @value   {Object} The object that will be serialized
]]
local function encode_schema(header, field, value)
   if value == nil or field.Schema == nil then 
      return ''
   end

   return table.concat({
      encode_field(header, field.Id, FIELD_TYPE_BITMASK_SCHEMA, false),
      serialize(value, field.Schema, false)
   }, '')
end

--[[
   Encodes a schema array type field, in the following format <{FIELD_REF}{SCHEMA_ID}[<[{VALUE}]{SCHEMA_END}>]>

   Where:

   FIELD_REF                     = FIELD_TYPE_BITMASK_SCHEMA, with IS_ARRAY=true
   SCHEMA_ID                     = byte
   [<[{VALUE}]{SCHEMA_END}>]     = Content array of each schema being serialized
                                    SCHEMA_END  = FIELD_TYPE_BITMASK_SCHEMA_END, marks the end of an item, uses the 
                                    IS_ARRAY bit to indicate whether it has more records in the sequence

   @header  {Object}    Header reference
   @field   {Object}    The reference for the field
   @values  {Object[]}  The objects that will be serialized
]]
local function encode_schema_array(header, field, values)
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
   Serializes a data

   A serialized message has the following structure 
      {HEADER}{SCHEMA_ID}[<{FIELD}[<{EXTRA}?[{VALUE}]?>]>]
      
   Where:
   
   HEADER {bit variable} 
      The header contains information about the displacement of the serialized bytes. The offset is necessary so that 
      the encoded bytes remain in the range of the 92 characters used. See `encode_byte(header, byte)`

   SCHEMA_ID {1 byte}   
      It is the message schema id, the system allows the creation of up to 255 (0 to 254) different schemes
   
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

   <{EXTRA}?[{VALUE}]?>
      EXTRA {1 byte}
      VALUE {bit variable}

      Additional definitions regarding the content, depends on the information contained in the FIELD

   VALUE {bit variable} 
      It is the serialized content itself


   @data    {Object} The data that will be serialized
   @schema  {Schema} Reference to the schema
   @hasMore {bool}   The schema end marker FIELD_TYPE_BITMASK_SCHEMA_END uses IS_ARRAY to tell if there is another 
                        serialized object in the sequence, used when it is a Schema array

   @return string
]]
serialize = function(data, schema, hasMore)
   if data == nil then 
      print('[WARNING] Schema:Serialize - Received nil as input, skipping serialization (Name='..schema.Name..')')
      return ''
   end

   local header = { index = 1, byte = HEADER_EMPTY_BYTE, content = {}}
   
   local out = {
      '',                             -- {HEADER} (replaced at the end of the run)
      encode_byte(header, schema.Id)  -- {SCHEMA_ID}
   }

   local value, content
   for _, field in ipairs(schema.Fields) do
      value = data[field.Name]
      if value ~= nil then
         
         if field.ConvertToSerialize ~= nil then 
            value = field.ConvertToSerialize(schema, field, value)
         end

         if value ~= nil then 
            -- <{FIELD}{EXTRA?}{VALUE?}...>
            content = field.EncodeFn(header, field, value)
            if content ~= '' then
               out[#out + 1] = content
            end
         end
      end
   end

   -- uses IS_ARRAY to tell you if you have more items
   out[#out + 1] = encode_field(header, 0, FIELD_TYPE_BITMASK_SCHEMA_END, hasMore)

   if #out == 3 then
      -- data is empty (only {HEADER}, {SCHEMA_ID} and {SCHEMA_END})
      return ''
   end

   header_flush(header)
   out[1] = header.content
   return table.concat(out, '')
end

--[[
   Utility to set the value of an object field during deserialization
]]
local function set_object_value(object, value, schema, fieldDecoded)
   if schema ~= nil then 
      local field = schema.FieldsById[fieldDecoded.Id]
      if field ~= nil then
         if field.Type == fieldDecoded.Type and field.IsArray == fieldDecoded.IsArray then
            
            if field.ConvertToInstance ~= nil then
               value = field.ConvertToInstance(schema, field, value)
            end

            object[field.Name] = value
         else
            print(table.concat({
               '[WARNING] StructDef:Deserialize - The type of the field is different from the serialized value (',
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
   De-serializes a content.

   It is allowed that there are several serialized records concatenated in the content, the system by default will 
   return only the first record.
   
   If you want an array with all existing records to be returned, just enter `true` in the` all` parameter, so the 
   method will always return an array

   @content {string} Serialized content
   @all     {bool}   Allows you to return all records that are concatenated in this content

   @return {Object|Array<Object>} if `all` = `true` returns array with all records concatenated in the content
]]
local function deserialize(content, all)

   -- the header data that has been deserialized
   local header            = { 
      shift = {}, 
      index = 1
   } 
   local fieldDecoded      = nil    -- raw field data, obtained from the function `decode_field(header, char)`
   local inHeader          = true   -- is processing the header?
   local inHeaderBit2      = false  -- the header identifies the shift of a byte, see the function `encode_byte`
   local schemaId          = nil    -- The schema id being processed, right after {HEADER}
   local schema            = nil    -- The reference to the Schema being processed
   local inExtraByte       = false  -- is processing EXTRA
   local extraByteDecoded  = nil    -- EXTRA data processed
   local isCaptureBytes    = false  -- is capturing bytes
   local capturedBytes     = {}     -- the captured bytes
   local isCaptureChars    = false  -- is capturing UTF-8 chars
   local capturedChars     = {}     -- the captured chars
   local captureCount      = 0      -- how many items is next to capture
   local value             = nil    -- the reference to the current field value
   local object            = {}     -- the reference to the current object
   local stack             = {}     -- the path to the nested objects
   local i                 = 0      -- auxiliary, just to identify the position if there is inconsistency


   local allObjects = {}

  

   for char in content:gmatch(utf8.charpattern) do
      i = i+1

      ------------------------------------------------------------------------------------------------------------------
      -- HEADER
      ------------------------------------------------------------------------------------------------------------------
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

      ------------------------------------------------------------------------------------------------------------------
      -- SCHEMA_ID
      ------------------------------------------------------------------------------------------------------------------
      elseif schemaId == nil then
         schemaId = decode_char(header, char)
         schema   = SCHEMA_BY_ID[schemaId]

         -- checks if the schema is registered
         if schema == nil and all ~= true then 
            print('[WARNING] StructDef:Deserialize - Content references to an unregistered schema (SCHEMA_ID='..schemaId..')')
            return nil
         end

      ------------------------------------------------------------------------------------------------------------------
      -- EXTRA
      ------------------------------------------------------------------------------------------------------------------
      elseif inExtraByte then

         inExtraByte = false
         local extraByte = decode_char(header, char)

         ---------------------------------------------------------------------------------------------------------------
         -- int32 [EXTRA]
         ---------------------------------------------------------------------------------------------------------------
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
                  -- Integer less than 64, fit in EXTRA
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

         ---------------------------------------------------------------------------------------------------------------
         -- int53 [EXTRA]
         ---------------------------------------------------------------------------------------------------------------
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

         ---------------------------------------------------------------------------------------------------------------
         -- double [EXTRA]
         ---------------------------------------------------------------------------------------------------------------
         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_DOUBLE then

            extraByteDecoded = decode_double_extra_byte(extraByte)
            -- Bytes
            isCaptureBytes    = true
            capturedBytes     = {}

            if extraByteDecoded.IsBig then 
               captureCount = extraByteDecoded.BytesTimes + extraByteDecoded.BytesRest
            else
               captureCount = extraByteDecoded.BytesRest
            end

            if extraByteDecoded.HasDec then
               captureCount = captureCount + extraByteDecoded.BytesDec
            end

            if fieldDecoded.IsArray then
               -- Bytes
               if value == nil then 
                  value = {}
               end      
            end

         ---------------------------------------------------------------------------------------------------------------
         -- string [EXTRA]
         ---------------------------------------------------------------------------------------------------------------
         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_STRING then
            if fieldDecoded.IsArray and fieldDecoded.Count == nil then
               -- The first EXTRA is the number of items, see `encode_string_array(header, field, values)`
               fieldDecoded.Count = extraByte
               value = {}
               -- next byte is an EXTRA too
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

      ------------------------------------------------------------------------------------------------------------------
      -- CAPTURING BYTES
      ------------------------------------------------------------------------------------------------------------------
      elseif isCaptureBytes then
         capturedBytes[#capturedBytes + 1] = decode_char(header, char)
         captureCount = captureCount - 1

         if captureCount == 0 then 
            isCaptureBytes = false

            ------------------------------------------------------------------------------------------------------------
            -- int32 [bytes]
            ------------------------------------------------------------------------------------------------------------
            if fieldDecoded.Type == FIELD_TYPE_BITMASK_INT32 then

               if fieldDecoded.IsArray then
                  value[#value + 1] = decode_int32_bytes(
                     capturedBytes, 
                     extraByteDecoded.Items[extraByteDecoded.Index].IsNegative
                  )

                  if extraByteDecoded.Items[extraByteDecoded.Index].HasMore then
                     extraByteDecoded.Index  = extraByteDecoded.Index + 1
                     if extraByteDecoded.Index > 2 then 
                        -- only 2 int32 per extra
                        inExtraByte = true
                     else
                        -- captures bytes of the next int32 in the sequence
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

            ------------------------------------------------------------------------------------------------------------
            -- int53 [bytes]
            ------------------------------------------------------------------------------------------------------------
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

            ------------------------------------------------------------------------------------------------------------
            -- double [bytes]
            ------------------------------------------------------------------------------------------------------------
            elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_DOUBLE then
               if fieldDecoded.IsArray then
                  value[#value + 1] = decode_double_bytes(capturedBytes, extraByteDecoded) 
                  if extraByteDecoded.HasMore then
                     inExtraByte = true
                  else
                     set_object_value(object, value, schema, fieldDecoded)
                     value = nil
                     extraByteDecoded = nil
                  end
               else
                  value = decode_double_bytes(capturedBytes, extraByteDecoded) 
                  set_object_value(object, value, schema, fieldDecoded)
                  value = nil
                  extraByteDecoded = nil
               end

            elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_BOOL_ARRAY then
               local hasMore = decode_bool_array_byte(capturedBytes[1], value)
               if hasMore then
                  isCaptureBytes = true
                  capturedBytes  = {}
                  captureCount   = 1
               else 
                  -- bool array has no more data
                  set_object_value(object, value, schema, fieldDecoded)
                  value             = nil
                  fieldDecoded      = nil
                  extraByteDecoded  = nil
               end
            end
         end

      ------------------------------------------------------------------------------------------------------------------
      -- CAPTURING CHARS (string only)
      ------------------------------------------------------------------------------------------------------------------
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

      ------------------------------------------------------------------------------------------------------------------
      -- FIELD or SCHEMA END
      ------------------------------------------------------------------------------------------------------------------
      else
         -- in field
         fieldDecoded = decode_field_byte(decode_char(header, char))
         inExtraByte = true

         if fieldDecoded.Type == FIELD_TYPE_BITMASK_BOOL then
            -- the bool type saves the value in the same byte as the field
            value = fieldDecoded.IsArray
            fieldDecoded.IsArray = false
            set_object_value(object, value, schema, fieldDecoded)            
            value       = nil 
            inExtraByte = false  -- has no extra byte
            
         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_BOOL_ARRAY then
            value          = {}
            isCaptureBytes = true
            capturedBytes  = {}
            captureCount   = 1
            inExtraByte = false  -- has no extra byte

         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_SCHEMA then
            inExtraByte = false  -- has no extra byte

            if fieldDecoded.IsArray then 
               value = {}
            else
               value = nil
            end

            -- save the current state
            local entry = {}
            entry.header            = header
            entry.fieldDecoded      = fieldDecoded
            entry.inHeader          = inHeader
            entry.inHeaderBit2      = inHeaderBit2
            entry.schemaId          = schemaId
            entry.schema            = schema
            entry.inExtraByte       = inExtraByte
            entry.extraByteDecoded  = extraByteDecoded
            entry.isCaptureBytes    = isCaptureBytes
            entry.captureCount = captureCount
            entry.capturedBytes     = capturedBytes
            entry.value             = value
            entry.object            = object
            entry.isCaptureChars    = isCaptureChars
            entry.capturedChars     = capturedChars
            table.insert(stack, entry)

            -- reset the variables
            header            = { shift = {}, index = 1}
            fieldDecoded      = nil
            inHeader          = true
            inHeaderBit2      = false
            schemaId          = nil
            schema            = nil
            inExtraByte       = false
            extraByteDecoded  = nil
            isCaptureBytes    = false
            captureCount = 0
            capturedBytes     = {}
            value             = nil 
            object            = {}
            isCaptureChars    = false
            capturedChars     = {}

         elseif fieldDecoded.Type == FIELD_TYPE_BITMASK_SCHEMA_END then
            inExtraByte = false  -- has no extra byte

            -- default values
            if schema ~= nil then
               -- forces default values for each field in the schema
               for _, field in ipairs(schema.Fields) do
                  local name = field.Name
                  if object[name] == nil then
                     object[name] = field.Default
                  end
               end
            end

            local parent = stack[#stack]

            if parent == nil then
               if all == true then 
                  table.insert(allObjects, object)
               else
                  return object
               end
            else
               if parent.fieldDecoded.IsArray then
                  table.insert(parent.value, object)
   
                  local hasMore = fieldDecoded.IsArray
                  if hasMore then
                     -- reset the variables
                     header            = { shift = {}, index = 1}
                     fieldDecoded      = nil
                     inHeader          = true
                     inHeaderBit2      = false
                     schemaId          = nil
                     schema            = nil
                     inExtraByte       = false
                     extraByteDecoded  = nil
                     isCaptureBytes    = false
                     captureCount      = 0
                     capturedBytes     = {}
                     value             = nil 
                     object            = {}
                     isCaptureChars    = false
                     capturedChars     = {}
                  else 
                     -- resets the parent variables
                     header            = parent.header
                     fieldDecoded      = parent.fieldDecoded
                     inHeader          = parent.inHeader
                     inHeaderBit2      = parent.inHeaderBit2
                     schemaId          = parent.schemaId
                     schema            = parent.schema
                     inExtraByte       = parent.inExtraByte
                     extraByteDecoded  = parent.extraByteDecoded
                     isCaptureBytes    = parent.isCaptureBytes
                     captureCount      = parent.captureCount
                     capturedBytes     = parent.capturedBytes
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

                  -- reset the variables
                  header            = parent.header
                  fieldDecoded      = parent.fieldDecoded
                  inHeader          = parent.inHeader
                  inHeaderBit2      = parent.inHeaderBit2
                  schemaId          = parent.schemaId
                  schema            = parent.schema
                  inExtraByte       = parent.inExtraByte
                  extraByteDecoded  = parent.extraByteDecoded
                  isCaptureBytes    = parent.isCaptureBytes
                  captureCount      = parent.captureCount
                  capturedBytes     = parent.capturedBytes
                  value             = parent.value
                  object            = parent.object
                  isCaptureChars    = parent.isCaptureChars
                  capturedChars     = parent.capturedChars
               end
            end
         end
      end
   end

   if all == true then 
      return allObjects
   end

   return object
end

local Schema = {}
Schema.__index = Schema

local function parse_primitive_field(fieldType, field, options)

   local defaultValue   = options.Default
   local maxLength      = options.MaxLength
   
   if fieldType == 'int32' then 
      field.EncodeFn = encode_int32
      field.Type     = FIELD_TYPE_BITMASK_INT32
      if defaultValue == nil then 
         defaultValue  = 0
      end
      
   elseif fieldType == 'int32[]' then 
      field.IsArray  = true
      field.EncodeFn = encode_int32_array
      field.Type     = FIELD_TYPE_BITMASK_INT32
      if defaultValue == nil then 
         defaultValue  = {}
      end
      
   elseif fieldType == 'int53' then 
      field.EncodeFn = encode_int53
      field.Type     = FIELD_TYPE_BITMASK_INT53
      if defaultValue == nil then 
         defaultValue  = 0
      end

   elseif fieldType == 'int53[]' then 
      field.IsArray  = true
      field.EncodeFn = encode_int53_array
      field.Type     = FIELD_TYPE_BITMASK_INT53
      if defaultValue == nil then 
         defaultValue  = {}
      end
      
   elseif fieldType == 'double' then 
      field.EncodeFn = encode_double
      field.Type     = FIELD_TYPE_BITMASK_DOUBLE
      if defaultValue == nil then 
         defaultValue  = 0.0
      end
   
   elseif fieldType == 'double[]' then 
      field.IsArray  = true
      field.EncodeFn = encode_double_array
      field.Type     = FIELD_TYPE_BITMASK_DOUBLE
      if defaultValue == nil then 
         defaultValue  = {}
      end

   elseif fieldType == 'bool' then
      field.EncodeFn = encode_bool
      field.Type     = FIELD_TYPE_BITMASK_BOOL
      if defaultValue == nil then 
         defaultValue  = false
      end

   elseif fieldType == 'bool[]' then
      field.IsArray  = true
      field.EncodeFn = encode_bool_array
      field.Type     = FIELD_TYPE_BITMASK_BOOL_ARRAY
      if defaultValue == nil then 
         defaultValue  = {}
      end
      
   elseif fieldType == 'string' or fieldType == 'string[]' then

      field.Type        = FIELD_TYPE_BITMASK_STRING
      field.MaxLength   = STRING_MAX_SIZE

      local maxLength = maxLength
      if maxLength ~= nil and type(maxLength) == 'number' then
         field.MaxLength = math.floor(maxLength)
         if field.MaxLength <= 0 then
            field.MaxLength = STRING_MAX_SIZE
         end 
         field.MaxLength = math.min(field.MaxLength, STRING_MAX_SIZE)
      end

      if fieldType == 'string' then 
         field.EncodeFn = encode_string
         if defaultValue == nil then 
            defaultValue  = ''
         end
      else
         field.IsArray  = true
         field.EncodeFn = encode_string_array
         if defaultValue == nil then 
            defaultValue  = {}
         end
      end
   else
      return false
   end

   field.Default = defaultValue

   return true
end

--[[
   Permite adicionar um campo no Schema
]]
function Schema:Field(id, name, fieldType, options)

   if options == nil then
      options = {}
   end
   
   if id == nil or type(id) ~= 'number' or math.floor(id) ~= id or id < 0 or id > 15 then
      error('Field Id must be an integer between 0 and 15')
   end
      
   if name == nil or  type(name) ~= 'string' or name == '' then
      error('Field Name must be a valid string')
   end

   if fieldType == nil then 
      error('Field data type is required')
   end

   for _, field in ipairs(self.Fields) do
      if field.Name == name then 
         error('A registered field with the same name already exists '..name)
      end

      if field.Id == id then 
         error('There is already a registered field with the same id '..id)
      end
   end

   local field    = {}
   field.Id       = id
   field.Name     = name
   field.IsArray  = false

   if parse_primitive_field(fieldType, field, options) then
      -- is primitive - OK
   elseif fieldType.isSchema then
      -- schema ref
      field.Type     = FIELD_TYPE_BITMASK_SCHEMA
      field.Schema   = fieldType

      if options.IsArray then
         field.IsArray  = true
         field.EncodeFn = encode_schema_array
      else
         field.EncodeFn = encode_schema
      end

   else
      -- Verifica se é referencia para Vector3 ou outras classes padrões do Roblox
      local converter = Converters[fieldType]
      if converter == nil then
         error('Field data type is invalid')
      end
      
      if options.IsArray then 
         parse_primitive_field(converter[2][1], field, options)
         field.Default              = converter[2][2]
         field.ConvertToSerialize   = converter[2][3]
         field.ConvertToInstance    = converter[2][4]
      else 
         parse_primitive_field(converter[1][1], field, options)
         field.Default              = converter[1][2]
         field.ConvertToSerialize   = converter[1][3]
         field.ConvertToInstance    = converter[1][4]
      end
   end 
   
   if field.ConvertToSerialize == nil and type(options.ToSerialize) == 'function' then
      field.ConvertToSerialize = options.ToSerialize
   end

   if field.ConvertToInstance == nil and type(options.ToInstance) == 'function' then 
      field.ConvertToInstance = options.ToInstance
   end

   table.insert(self.Fields, field)
   self.FieldsById[field.Id] = field

   return self
end

function Schema:Serialize(data)
   return serialize(data, self, false)
end

--[[
   Register a new schema

   Params
      id       {byte|Object}   The schema identifier or configuration
]]
local function CreateSchema(id)

   if type(id) == 'number' then
      if id < 0  or id > 254 then
         error('The schema id must be> = 0 and <= 254')
      end
         
      if SCHEMA_BY_ID[id] ~= nil then
         error('There is already a registered schema with the given Id')
      end
   
      local schema      = {}
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
      if config.Fields ~= nil then
         for name, params in pairs(config.Fields) do 
            schema:Field(params.Id, name, params.Type, { 
               Default     = params.Default,
               MaxLength   = params.MaxLength,
               ToSerialize = params.ToSerialize,
               ToInstance  = params.ToInstance
            })
         end
      end

      return schema      
   end
end

local StructDef = {}
StructDef.Schema        = CreateSchema
StructDef.Deserialize   = deserialize
return StructDef
