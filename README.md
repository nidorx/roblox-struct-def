# Roblox Structure Definition - StructDef

**TLDR;** 

```lua
local StructDef = require(game.ReplicatedStorage:WaitForChild("StructDef"))

local MySchema = StructDef.Schema(1)
   :Field(0, 'Points',    'int32')
   :Field(1, 'WeaponIds', 'int32[]')

local data = {
  Points    = 35625737,
  WeaponIds = {13883, 33655, 6533, 75567}
} 

local serialized = MySchema:Serialize(data)

-- prints "A@ha`=#c.$Ab+txX^I={;K#IQJ"
print(serialized) 

local deserialized = StructDef.Deserialize(serialized)
print(deserialized)
```

## Links

- **Latest stable version**
    - https://www.roblox.com/library/ID_LIBRARY/StructDef
- **Forum**
    - https://devforum.roblox.com/t/ID_FORUM
- **Releases**
   - https://github.com/nidorx/roblox-struct-def/releases
    
## Installation

You can do the installation directly from Roblox Studio, through the Toolbox search for `StructDef`, this is the minified version of the engine (https://www.roblox.com/library/ID_LIBRARY/StructDef).

If you want to work with the original source code (for debugging or working on improvements), access the repository at https://github.com/nidorx/roblox-struct-def

## What is StructDef

The Structure Definition, or simply StructDef, is a library that allows the serialization and deserialization of structured data. You define how you want your data to be structured once and then you can use the generated instance to easily write and read your structured data to and from a UTF-8 string.

## Use cases

StructDef was developed with the aim of simplifying the serialization and deserialization of complex objects using a standard language. In addition to being simple, StructDef generates an optimized output to be used in services such as [Data Stores](https://developer.roblox.com/en-us/articles/Data-store) and [MessagingService](https://developer.roblox.com/en-us/api-reference/class/MessagingService) of Roblox, which has limitations related to the size of the message sent.

StructDef can be used to:

- Generate less boilerplate code
  - A suitable StructDef scheme helps to reduce the boilerplate code and thereby improve performance in the long term.
- Reduce network traffic
  - Data serialized with StructDef is very small. StructDef only saves in the output string the information necessary for its future deserialization
- Package the messages that will be sent via MessagingService 
  - StructDef allows multiple serialized data to be concatenated in sequence, and all of them can be deserialized at once by passing `true` as the second parameter of the `StructDef.Deserialize(content, all)` method, so it is possible to take advantage of the entire band available (1KB) for transporting diverse messages efficiently
- Persist data in Data Stores
  - By generating a smaller output, data serialized by StructDef is saved and read faster from Data Stores, if compared to a serialization using JSON for example


StructDef may not be recommended for large data structures that need to be serialized at all times (for each frame, for example), because StructDef does strong validation of the input data and makes heavy use of [bit manipulation](https://developer.roblox.com/en-us/api-reference/lua-docs/bit32) in order to guarantee serializing numbers with varying size of bytes. The recommendation is that you do tests in order to find out if StructDef will penalize its functionality.

**For less complex data structures the impact of StructDef is negligible**

## Defining A Schema

Defining a Schema in StructDef is very simple. Just create the Schema and add the fields according to their structure.

```lua
local PlayerSchema = StructDef.Schema(1)
   :Field(0,   'Name',         'string', { MaxLength = 100 })
   :Field(1,   'TimeInGame',   'int53')
   :Field(2,   'Experience',   'int53')
   :Field(3,   'Money',        'int53')
```

Optionally, you can define the schema declaratively, the result is the same.

```lua
local PlayerSchema = StructDef.Schema({
  Id      = 1,
  Fields  = {
    Name        = { Id = 0, Type = 'string', MaxLength = 100 },
    TimeInGame  = { Id = 1, Type = 'int53' },
    Experience  = { Id = 2, Type = 'int53' },
    Money       = { Id = 3, Type = 'int53' }
  },
})
```

### Fields

The general definition of a Schema's fields is

```lua
:Field(ID, NAME, TYPE, OPTIONS?)

-- or --

Fields = {
  {
    NAME = { 
      Id          = ID,
      Type        = TYPE,
      Default     = VALUE,
      MaxLength   = NUMBER,
      ToSerialize = function,
      ToInstance  = function
    }
  }
}
```

| Option            | Type        | Description |
| ----------------- | ----------- | ----------- |
| **`Default`**     | `any`       | Allows you to set the default value for the field |
| **`MaxLength`**   | `number`    | Only for the `string` and `string[]` types, allows you to define the maximum text size |
| **`ToSerialize`** | `function`  | Invoked before serializing a value, `function (schema, field, value): value` |
| **`ToInstance`**  | `function`  | Invoked after deserializing a value, `function (schema, field, value): value` |



> The `ToSerialize` and` ToInstance` methods allow customization of the data, both to serialize and to instantiate. Internally it is used in [Roblox standard type converters] (https://github.com/nidorx/roblox-schema/blob/main/src/Shared/Lib/Converters.lua)


### Assigning Ids

As you can see, in addition to Schema, each field has a unique number. These numbers are used to identify your scheme and fields in serialized format and should not be changed after your scheme is in use.

StructDef allows the definition of up to 255 schemas (from 0 to 254) and up to 16 fields per schema (from 0 to 15). At the time of serialization, the schema Id spends one byte to encode and the field id, which is encoded along with other information, consumes 4 more bits (you can find out more about this in [Structure Definition Encoding](ENCODING.md)).

### Specifying Field Types

The data types available for use in StructDef are defined below.


#### int32, int32[]

Allows you to define a 32-bit INTEGER field, with values from `-4,294,967,295` to `4,294,967,295` _(`-((2^32) -1)` to `(2^32) -1`)_

```lua
local MySchema = StructDef.Schema(1)
   :Field(0, 'Points',    'int32')
   :Field(1, 'WeaponIds', 'int32[]')

local data = {
  Points    = 35625737,
  WeaponIds = {13883, 33655, 6533, 75567}
}  

-- prints "A@ha`=#c.$Ab+txX^I={;K#IQJ"
print(MySchema:Serialize(data)) 
```


#### int53, int53[]

Allows you to define a 53-bit INTEGER field, with values from `-9,007,199,254,740,991` to `9,007,199,254,740,991` _(`-((2^53) -1)` to `(2^53) -1`)_

The `int53` (the **MAX SAFE INTEGER**), has a value of `9007199254740991` (`9,007,199,254,740,991` or ~9 quadrillion). The reasoning behind that number is that LUA uses [double-precision floating-point format numbers](https://en.wikipedia.org/wiki/Double-precision_floating-point_format) as specified in [IEEE 754](https://en.wikipedia.org/wiki/IEEE_754) and can only safely represent integers between `-(2^53 - 1)` and `2^53 - 1`.

Safe in this context refers to the ability to represent integers exactly and to correctly compare them. For example, `9007199254740991 + 1 == 9007199254740991 + 2` will evaluate to `true`, which is mathematically incorrect. See [NumberValue](https://developer.roblox.com/en-us/api-reference/class/NumberValue) for more information.


```lua
local MySchema = StructDef.Schema(1)
   :Field(0, 'EXP',     'int53')
   :Field(1, 'UserIds', 'int53[]')

local data = {
  EXP       = 47199254740991,
  UserIds = {13883, 33655, 6533, 75567}
}  

print(MySchema:Serialize(data))
```

#### double, double[]

[Double-precision floating-point number](https://en.wikipedia.org/wiki/Double-precision_floating-point_format), limited to four decimal places (n.1234). See [NumberValue](https://developer.roblox.com/en-us/api-reference/class/NumberValue) for more information.

```lua
local MySchema = StructDef.Schema(1)
   :Field(0, 'Elevation', 'double')
   :Field(1, 'Points',    'double[]')

local data = {
  Elevation = 5.666,
  Points    = {3.4253, 123.655, 7.75277, 8.7655}
}  

-- prints "PPdaCp=#F('<&W)%2d)A;]))?-(*?PJ"
print(MySchema:Serialize(data))
```

#### bool, bool[]

Booleans

```lua
local MySchema = StructDef.Schema(1)
   :Field(0, 'IsActive',  'bool')
   :Field(1, 'Flags',     'bool[]')

local data = {
  IsActive = true,
  Flags    = {true, false, true, false}
}  

-- prints "G`=#2SRJ"
print(MySchema:Serialize(data))
```

#### string, string[]

o StructDef Saves UTF-8 _AS IS_ text, without encoding

```lua
local MySchema = StructDef.Schema(1)
   :Field(0, 'Username',  'string')
   :Field(1, 'Messages',  'string[]')

local data = {
  Username  = 'nidorx',
  Messages  = {'Foo © bar 𝌆 baz ☃ qux!', "!#$%&'()*+,-./012"}
}  

print(MySchema:Serialize(data))
```

#### Schema

Allows you to use a schema as a data type. This allows the construction of complex structures.

```lua
local MarkSchema = StructDef.Schema(1)
   :Field(0, 'Elevation', 'double')
   :Field(1, 'Points',    'double[]')

local PetSchema = StructDef.Schema(2)
   :Field(0, 'EXP',     'int32')
   :Field(1, 'Buffers', 'int32[]')

local AvatarSchema = StructDef.Schema(3)
   :Field(0, 'Username',  'string')
   :Field(1, 'Mark',  MarkSchema)
   :Field(2, 'Pets',  PetSchema, { IsArray = true })

local data = {
  Username  = 'nidorx',
  Mark =  {
    Elevation = 5.666,
    Points    = {3.4253, 123.655, 7.75277, 8.7655}
  },
  Pets = {
    {
      EXP     = 456282,
      Buffers = {13883, 33655, 6533, 75567}
    },
    {
      EXP     = 471992547,
      Buffers = {1383, 33655, 6533, 75567}
    } 
  }
}  

-- prints "U~=%gLnidorx+PPdaCp=#F('<&W)%2d)A;]))?-(*?PJ<CAQC=$c*(a}txX^I={;K#IQZ@qTPp=$c.>D*Mtx'-I={;K#IQJJ"
print(AvatarSchema:Serialize(data)) 
```


#### RobloxType

StructDef allows the use of several standard [Roblox types](https://developer.roblox.com/en-us/api-reference/data-types) as a data type. Internally it is converted to one of the primitive types above.

> **Work in progress!**  You can contribute by creating new converters in the [Converters.lua](https://github.com/nidorx/roblox-schema/blob/main/src/Shared/Lib/Converters.lua)
 file and making a pull request

- Vector3
- <s>Vector3Value</s>
- <s>Vector2</s>
- <s>CFrame</s>
- <s>CFrameValue</s>
- <s>Color3</s>
- <s>Color3Value</s>
- <s>BrickColor</s>
- <s>DateTime</s>
- <s>Rect</s>
- <s>Region3</s>
- <s>Enum, EnumItem, Enums</s>
- <s>BoolValue</s>
- <s>BrickColorValue</s>
- <s>IntValue</s>
- <s>IntConstrainedValue</s>
- <s>NumberValue</s>
- <s>DoubleConstrainedValue</s>
- <s>StringValue</s>


```lua
local MySchema = StructDef.Schema(1)
   :Field(0, 'Velocity',    Vector3)
   :Field(1, 'CheckPoints', Vector3, { IsArray = true })

local data = {
  Velocity    = Vector3.new(0, 1.4, 0),
  CheckPoints = {
    Vector3.new(24.6678, 21.6678, 27.5678),
    Vector3.new(3.6678, 21.6678, 7.5678),
    Vector3.new(-90.8755, 23.1341, 543.7662),
  }
}  

-- prints "PH`@@@H@G`=#V#!)#1f!!W):<8)7<8)=8P)%<7)7<8))8PM}DU)9'_0$A?WJ"
print(MySchema:Serialize(data))
```

## Building your own StructDef

### To edit
1. Make sure Rojo 0.5.x or later is installed
2. Clone this repository to your computer
3. Set the location to this repo's root directory and run this command in CMD/PowerShell/Cmder:
    ```
    rojo serve
    ```
4. Create a new project on Roblox Studio and install Rojo Plugin, then, connect
5. Edit sources with Visual Studio Code, all changes will replicated automaticaly to Roblox Studio


### To build

In the terminal, enter the following:

```
npm install
npm run build
```

##  @TODO
- [ ] Improve documentation
- [ ] Create all Roblox Type converters
- [ ] UnitTest & Coverage
- [ ] Benchmark

## Feedback, Requests and Roadmap

Please use [GitHub issues] for feedback, questions or comments.

If you have specific feature requests or would like to vote on what others are recommending, please go to the [GitHub issues] section as well. I would love to see what you are thinking.

## Contributing

You can contribute in many ways to this project.

### Translating and documenting

I'm not a native speaker of the English language, so you may have noticed a lot of grammar errors in this documentation.

You can FORK this project and suggest improvements to this document (https://github.com/nidorx/roblox-struct-def/edit/master/README.md).

If you find it more convenient, report a issue with the details on [GitHub issues].

### Reporting Issues

If you have encountered a problem with this component please file a defect on [GitHub issues].

Describe as much detail as possible to get the problem reproduced and eventually corrected.

### Fixing defects and adding improvements

1. Fork it (<https://github.com/nidorx/roblox-struct-def/fork>)
2. Commit your changes (`git commit -am 'Add some fooBar'`)
3. Push to your master branch (`git push`)
4. Create a new Pull Request

## License

This code is distributed under the terms and conditions of the [MIT license](LICENSE).


[GitHub issues]: https://github.com/nidorx/roblox-struct-def/issues
