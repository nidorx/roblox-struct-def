import 'core-js'

type FieldTypes = 'int32'   | 'int32[]'     |
                  'int53'   | 'int53[]'     |
                  'double'  | 'double[]'    |
                  'bool'    | 'bool[]'      |
                  'string'  | 'string[]'    |
                  CFrame    | CFrame[]      |
                  Vector3   | Vector3[]     

declare class Schema {
    Field(id: number, name: string, fieldType: FieldTypes, options): this
    Serialize(data: any): string
}

declare class StructDef {
    static schema: Schema
    static deserialize(content: string, all?: boolean): any
    static deserialize(content: string, all: true): Array<any>
}

export = StructDef
