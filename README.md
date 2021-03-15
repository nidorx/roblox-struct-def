## Roblox Schema

Um Schema permite definir a estrutura de dados que deseja ser serializado. Os campos de um esquema pode ser de um dos tipos abaixo
    - int32     {-(2^32) a (2^32)-1}
    - int53     {-(2^53) a (2^53)}
    - double    {int53.{0 a 65535}}
    - boolean
    - string
    - SchemaRef

  Uma mensagem encodada tem a seguinte estrutura
    {HEADER}{SCHEMA_ID}<{FIELD}{EXTRA?}{VALUE?}...>
  
  Onde:
    SCHEMA_ID {8 bits} é o id do esquema da mensagem, o sistema permite a criação de até 255 esquemas distintos
    FIELD     {8 bits} é a definição da chave do campo do esquema
    EXTRA     {8 bits} Definições adicionais à respeito do conteúdo, nem sempre está presente, depende da informação contida na FIELD
    VALUE     {variable} É o próprio conteúdo

    FIELD
      Quando uma mensagem é codificada, as chaves e os valores são concatenados. Quando a mensagem está sendo decodificada, o analisador precisa ser capaz de pular os campos que não reconhece. Desta forma, novos campos podem ser adicionados a uma mensagem sem quebrar programas antigos que não os conhecem. Para esse fim, a "chave" para cada par em uma mensagem em formato de ligação é, na verdade, dois valores - o identificador do campo no schema, mais um tipo de ligação que fornece informações suficientes para encontrar o comprimento do valor a seguir.

      1 1 1 1 1 1 1 1
      |   | | |     |
      |   | | +-----+--- 4 bits para identificar o campo, portanto, um schema pode ter no máximo 16 campos (2^4)
      |   | |            
      |   | +----------- 1 bit  IS ARRAY flag que determina se é array
      +---+------------- 3 bits determina o tipo do dado

      
      DATA TYPE 
        |  code |    type    |
        | ----- | ---------- | 
        | 0 0 0 | bool FALSE |
        | 0 0 1 | bool TRUE  |
        | 0 1 0 | int32      |   
        | 0 1 1 | int53      |
        | 1 0 0 | double     |
        | 1 0 1 | string     |
        | 1 1 0 | SchemaRef  |
        | 1 1 1 | NÃO USADO  |

    EXTRA

      - boolean 
          - Não se aplica

      - Bool array
        1 1 1 1 1 1 1 1
        | | |     | | |
        | | |     | | +--- 1 bit TEM MAIS? Caso positivo, o proximo byte também  faz parte do array, mesma estrutura
        | | |     | | 
        | | |     | +----- descartado
        | | |     | 
        | | +-----+------- 4 bits que podem fazer parte do array
        | |
        +-+--------------- 2 bit (= 4 valores) determina quantos bits seguintes fazem parte do array

      - int32 ARRAY
        1 1 1 1 1 1 1 1
        | | | | | | | |
        | | | | | | | +--- 1 bit TEM MAIS? Caso positivo, o proximo byte também  faz parte do array, mesma estrutura
        | | | | | | | 
        | | | | | | +----- descartado
        | | | | | |
        | | | | +-+------- 2 bits (= 4 valores) quantos bytes [chars] é usado pelo 3º int32 na sequencia, caso 0 STOP
        | | | |
        | | +-+----------- 2 bits (= 4 valores) quantos bytes [chars] é usado pelo 2º int32 na sequencia, caso 0 STOP
        | |
        +-+--------------- 2 bits (= 4 valores) quantos bytes [chars] é usado pelo 1º int32 na sequencia

      - int32
        0 1 1 1 1 1 1 1
        | | | |       |
        | | | |       |
        | | | +-------+--- 5 bits descartado caso numero maior que 128
        | | |
        | +-+------------- 2 bits (= 4 valores) quantos bytes [chars] é usado pelo int32 na sequencia
        |
        +----------------- 1 bit número cabe nos proximos bits? Se número for <= 128 (2^7),
                            o seu conteúdo já é formado pelos proximos bit. Caso negativo, valida proximos 2 bits

                            A = valor normal (0 a 92)
                            B = slide 1 (95 a 184)
                            C = slide 2 (189 a 255)
                            0 0 0 0 0   = A A A A
                            0 0 0 0 0   = A A A B
                            0 0 0 0 0   = A A A C
                            0 0 0 0 0   = A A B A
                            0 0 0 0 0   = A A C A
                            0 0 0 0 0   = A B A A
                            0 0 0 0 0   = A C A A
                            0 0 0 0 0   = B A A A
                            0 0 0 0 0   = C A A A
                            1 1 1 1 1




    A B   A C
    0 1 0 0 1 1

32768
65535

String.fromCharCode(Number.parseInt('1000000000000000', 2))

  -- 
  0 1 0 0 0 0 0 0  - 64 - @
  0 1 0 1 1 1 1 1  - 95 - _


  local dictionary94 = {} 




  {HEADER}.<{KEY}{VALUE}...>



  local HEADER_SWAP = {
    {
      -- 01011100 = \
      string.char(92), 
      -- 00011100 = <
      string.char(60)
    },
    {
      -- 11111111 = DELETE
      string.char(92), 
      -- 00111111 = ?
      string.char(60)
    }
  }

 "0111110 - 62 - >",

  

    1_1_0 1_0_1



      - int53 ARRAY
        1 1 1 1 1 1 1 1 
        | | |       | |
        | | |       | +- 1 bit TEM MAIS? Caso positivo, o byte após o 2º int53 faz parte do array, mesma estrutura
        | | |       | 
        | | |       |
        | | |       |
        | | |       |
        | | |       |
        | | +-------+---- 5 bits quantos bytes [chars] é usado pelo 1º e 2º int53 na sequencia, conforme tabela abaixo
        | +-------------- 1 bit quantos int53 na sequencia (0 = 1, 1 = 2)
        +---------------- 1 bit IS ARRAY = true

          Tabela de distribuição de bytes para array

          (1 e 1) = 0 0 0 0 0
          (2 e 1) = 0 0 0 0 1
          (3 e 1) = 0 0 0 1 0
          (4 e 1) = 0 0 0 1 1
          (5 e 1) = 0 0 1 0 0
          (6 e 1) = 0 0 1 0 1
          (7 e 1) = 0 0 1 1 0
          (1 e 2) = 0 0 1 1 1
          (1 e 3) = 0 1 0 0 0
          (1 e 4) = 0 1 0 0 1
          (1 e 5) = 0 1 0 1 0
          (1 e 6) = 0 1 0 1 1
          (1 e 7) = 0 1 1 0 0
          (2 e 2) = 0 1 1 0 1
          (3 e 3) = 0 1 1 1 0
          (4 e 4) = 0 1 1 1 1
          (5 e 5) = 1 0 0 0 0
          (6 e 6) = 1 0 0 0 1
          (7 e 7) = 1 0 0 1 0

      - int53
        1 1 1 1 1 1 1 1
        |   | | |     |
        |   | | |     |
        |   | | |     |
        |   | | |     |
        |   | | |     |
        |   | | +-----+--- Descartado
        |   | |
        |   | +----------- 1 bit byte mais significativo cabe nos proximos bits 4?
        +---+------------- 3 bits (= 8 valores) quantos bytes [chars] é usado pelo int53 na sequencia


      - double
      - string
        0 1 1 1 1 1 1 1
        | |   | |     |
        | |   | |     |
        | |   | |     |
        | |   | |     |
        | |   | |     |
        | |   | +-----+-- Descartado
        | |   |
        | +---+---------- 3 bits (= 8 valores) quantos bytes [chars] é usado pelo int64 na sequencia
        |
        +---------------- 1 bit IS ARRAY = false

      - SchemaRef

      1 1 1 1 1 1 1 1
      | | | | | | | |
      | | | | | | | +--
      | | | | | | +----
      | | | | | +------
      | | | | +--------
      | | | +----------
      | | +------------
      | +--------------
      +---------------- IS ARRAY ?
  

    KEY_ID ENCODED_VALUE

-- INT32 = | 1 1 1 1 1 1 1 1 | 1 1 1 1 1 1 1 1 | 1 1 1 1 1 1 1 1 | 1 1 1 1 1 1 1 1 |

-- Double interger = 2^52
-- INT52 = | 1 1 1 1 1 1 1 1 | 1 1 1 1 1 1 1 1 | 1 1 1 1 1 1 1 1 | 1 1 1 1 1 1 1 1 | 1 1 1 1 1 1 1 1 | 1 1 1 1 1 1 1 1 | 1 1 1 1 1 

-- STRING = Unlimited

1 1 1 1 1 1 1 1
| | | | | | | |
| | | | | | | +---
| | | | | | +-----
| | | | | +-------
| | | | +---------
| | | +-----------
| | +-------------
| +---------------
+-----------------




A informação sobre o tamanho do caractere é salvo em um caractere UTF-8 de 2 bytes
-- https://design215.com/toolbox/ascii-utf8.php
1 1 1 1 1 1 1 1
| | | | | | | |
| | | | | | | +--- has more?
| | | | | | +-----
| | | | | +-------
| | | | +---------
| | | +-----------
| | +-------------
| +--------------- Se 0 menor que 184 (incrementa 92), se 1 maior que 92 (incremente 184)
+----------------- Se 0, menor que 92, se 1 valida proximo
