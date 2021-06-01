# Advanced Programming Second Project

TODOs:
- [X] Add instance methods- [X] Only declare static methods in module, if we can
- [X] Only generate module if module hasn't been imported
- [X] Do not reimport a module
- [X] Methods with arrays???
- [X] Typify method arguments?
- [X] Import modules as needed, for example: Datetime.now().getMonth() returns a Month
- [X] Get all constructors
- [X] getfields ao importar (class constants)
- [X] include path issue
- [ ] Convert jboolean to Bool
- [X] Allow direct conversion from String to JString i.e. JString("hello")
- [ ] What about Arrays of anything?
- [X] When calling a method, transform the JavaValue to its reference (i.e.: Datetime.of(Int32(2021), Month.FEBRUARY, Int32(28)) does not work, but
  this Datetime.of(Int32(2021), getfield(Month.FEBRUARY, :ref), Int32(28)) works)
- [ ] Duplicate the methods that can receive a JObject to allow them
- [ ] Duplicate the methods that can receive a JString to allow either a String or a JavaValue of String

TODOs bacanos não obrigatórios:
- [ ] Apanhar as exceções, try catch + print(exception.getMessage())
- [ ] Criar? methods para mostrar os métodos da instância ou da classe?

StringModule = importJavaLib("java.lang.String") manda ERROR: LoadError: UndefVarError: Lookup not defined
