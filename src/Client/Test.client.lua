repeat wait() until game.Players.LocalPlayer.Character

-- Player, Workspace & Environment
local Players 	   = game:GetService("Players")
local Player 	   = Players.LocalPlayer
local Character   = Player.Character
local Humanoid 	= Character:WaitForChild("Humanoid")
local Camera 	   = workspace.CurrentCamera
local HttpService = game:GetService("HttpService")

-- lib
local Schema = require(game.ReplicatedStorage:WaitForChild('Schema'))


local schema = Schema.Create(1)
   :Field(1,   'BoolTrue',         'bool', false)
   :Field(2,   'BoolFalse',        'bool', false)
   :Field(3,   'BoolArray2',       'bool',  true)
   :Field(4,   'BoolArray4',       'bool',  true)
   :Field(5,   'BoolArray7',       'bool',  true)
   :Field(6,   'Int33',            'int32', false)
   :Field(7,   'Int60Neg',         'int32', false)
   :Field(8,   'Int32Byte1',       'int32', false)
   :Field(9,   'Int32Byte2',       'int32', false)
   :Field(10,  'Int32Byte3',       'int32', false)
   :Field(11,  'Int32Byte4',       'int32', false)
   :Field(12,  'Int32Array',       'int32', true)


local schemaParent = Schema.Create(2)
   :Field(1,   'Child',             schema, false)
   :Field(2,   'ChildArray',        schema, true)
   :Field(3,   'Int53Byte0',       'int53', false)
   :Field(4,   'Int53Byte1',       'int53', false)
   :Field(5,   'Int53Byte2',       'int53', false)
   :Field(6,   'Int53Byte3',       'int53', false)
   :Field(7,   'Int53Byte4',       'int53', false)
   :Field(8,   'Int53Byte5',       'int53', false)
   :Field(9,   'Int53Byte6',       'int53', false)
   :Field(10,  'Int53Array',       'int53', true)
   :Field(11,  'StringAscii',      'string', false)
   :Field(12,  'StringUtf8',       'string', false)
   :Field(13,  'StringBig',        'string', false)
   :Field(14,  'StringArray',      'string', true)


local childContent = {
   BoolTrue = true, 
   BoolFalse = false,
   BoolArray2 = { true, false},
   BoolArray4 = { true, false, true, false},
   BoolArray7 = { true, false, true, false, true, false, true },
   Int33 = 33,
   Int60Neg = -60,
   Int32Byte1 = 128,
   Int32Byte2 = 32896,
   Int32Byte3 = 8421504,
   Int32Byte4 = 2155905152,
   Int32Array = {32, 64, 128, 32896, 8421504, 2155905152, -32, -64, -128, -32896, -8421504, -2155905152}
}

local childContent2 = {
   BoolTrue = true, 
   BoolFalse = false,
   BoolArray2 = { true, false},
   BoolArray4 = { true, false, true, false},
   BoolArray7 = { true, false, true, false, true, false, true },
   
}

local parentContent = {
   Child = childContent,
   ChildArray = { childContent, childContent2 },
   Int53Byte0 = 60,
   Int53Byte1 = 255,
   Int53Byte2 = 65535,
   Int53Byte3 = 16777215,
   Int53Byte4 = 4294967295,
   Int53Byte5 = 1099511627775,
   Int53Byte6 = 281474976710655,
   Int53Array = {
      60, 255, 65535, 16777215, 4294967295, 1099511627775, 281474976710655,
      -60, -255, -65535, -16777215, -4294967295, -1099511627775, -281474976710655
   },
   StringAscii = "!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~",
   StringUtf8  = 'Foo © bar 𝌆 baz ☃ qux',
   StringBig   = [[!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~Foo © bar 𝌆 baz ☃ qux!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~Foo © bar 𝌆 baz ☃ qux!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~Foo © bar 𝌆 baz ☃ qux!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~Foo © bar 𝌆 baz ☃ qux]],
   StringArray = {
      'Foo',
      '© bar ',
      '𝌆 baz ☃',
      'qux',
      'jose',
   }
}

local serialized = schemaParent:Serialize(parentContent)

print('serialized', serialized, utf8.len(serialized))
local deserialized = Schema.Deserialize(serialized)
print('deserialized', deserialized)


local json = HttpService:JSONEncode(parentContent)
print('json', json, utf8.len(json))


--[[
@TODO
   [x] bool
   [x] bool[]
   [x] int32
   [x] int32[]
   [x] int53
   [x] int53[]
   [ ] double
   [ ] double[]
   [x] string
   [x] string[]
   [x] ref
   [x] ref[]
   -- roblox DataTypes - https://developer.roblox.com/en-us/api-reference/data-types
   [ ] Vector2
   [ ] Vector3
   [ ] CFrame
   [ ] Color3
   [ ] BrickColor
   [ ] DateTime
   [ ] Rect
   [ ] Region3
   [ ] Enum, EnumItem, Enums
   [ ] BoolValue
   [ ] CFrameValue
   [ ] Vector3Value
   [ ] Color3Value
   [ ] BrickColorValue
   [ ] IntValue
   [ ] IntConstrainedValue
   [ ] NumberValue
   [ ] DoubleConstrainedValue
   [ ] StringValue
]]




