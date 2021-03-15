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


local schemaChild = Schema.Create(1)
   :Field(1,   'BoolTrue',          'bool')
   :Field(2,   'BoolFalse',         'bool')
   :Field(3,   'BoolArray2',        'bool[]')
   :Field(4,   'BoolArray4',        'bool[]')
   :Field(5,   'BoolArray7',        'bool[]')
   :Field(6,   'Int33',             'int32')
   :Field(7,   'Int60Neg',          'int32')
   :Field(8,   'Int32Byte1',        'int32')
   :Field(9,   'Int32Byte2',        'int32')
   :Field(10,  'Int32Byte3',        'int32')
   :Field(11,  'Int32Byte4',        'int32')
   :Field(12,  'Int32Array',        'int32[]')
   :Field(13,  'Double',            'double')
   :Field(14,  'DoubleBig',         'double')
   :Field(15,  'DoubleArray',       'double[]')


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
   BoolTrue    = true, 
   BoolFalse   = false,
   BoolArray2  = { true, false},
   BoolArray4  = { true, false, true, false},
   BoolArray7  = { true, false, true, false, true, false, true },
   Double      = 5.666,
   DoubleBig   = 281474976710655.345623,
   DoubleArray = {
      5.666, 32896.8421504, 2155905152.32896, 281474976710655.345623,
      -5.666, -32896.8421504, -2155905152.32896, -281474976710655.345623
   }
}

local schemaObjects = Schema.Create(3)
   :Field(0,   'Vector3',          Vector3)
   :Field(1,   'Vector3Array',     Vector3, true)

local objectContent = {
   Vector3        = Vector3.new(1.111, 2.222, 3.333),
   Vector3Array   = {
      Vector3.new(1.111, 2.222, 3.333),
      Vector3.new(-1.111, -2.222, -3.333)
   }
}

local schemaParent = Schema.Create(2)
   :Field(0,   'Object',            schemaObjects)
   :Field(1,   'Child',             schemaChild)
   :Field(2,   'ChildArray',        schemaChild, true)
   :Field(3,   'Int53Byte0',       'int53')
   :Field(4,   'Int53Byte1',       'int53')
   :Field(5,   'Int53Byte2',       'int53')
   :Field(6,   'Int53Byte3',       'int53')
   :Field(7,   'Int53Byte4',       'int53')
   :Field(8,   'Int53Byte5',       'int53')
   :Field(9,   'Int53Byte6',       'int53')
   :Field(10,  'Int53Array',       'int53[]')
   :Field(11,  'StringAscii',      'string')
   :Field(12,  'StringUtf8',       'string')
   :Field(13,  'StringBig',        'string')
   :Field(14,  'StringArray',      'string[]')

local parentContent = {
   Object      = objectContent,
   Child       = childContent,
   ChildArray  = { childContent, childContent2 },
   Int53Byte0  = 60,
   Int53Byte1  = 255,
   Int53Byte2  = 65535,
   Int53Byte3  = 16777215,
   Int53Byte4  = 4294967295,
   Int53Byte5  = 1099511627775,
   Int53Byte6  = 281474976710655,
   Int53Array  = {
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


-- local json = HttpService:JSONEncode(parentContent)
-- print('json', json, utf8.len(json))

--[[
@TODO
   [x] bool
   [x] bool[]
   [x] int32
   [x] int32[]
   [x] int53
   [x] int53[]
   [x] double
   [x] double[]
   [x] string
   [x] string[]
   [x] ref
   [x] ref[]
   -- roblox DataTypes - https://developer.roblox.com/en-us/api-reference/data-types
   [ ] Vector3
   [ ] Vector3Value
   [ ] Vector2
   [ ] CFrame
   [ ] Color3
   [ ] BrickColor
   [ ] DateTime
   [ ] Rect
   [ ] Region3
   [ ] Enum, EnumItem, Enums
   [ ] BoolValue
   [ ] CFrameValue
   [ ] Color3Value
   [ ] BrickColorValue
   [ ] IntValue
   [ ] IntConstrainedValue
   [ ] NumberValue
   [ ] DoubleConstrainedValue
   [ ] StringValue
]]




