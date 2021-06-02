include("src/project.jl")
using Main.project, JavaCall

Math = importJavaLib("java.lang.Math")
Math.min(1, 2)
Math.min(1.3, 1.2)

LocalDate = importJavaLib("java.time.LocalDate")
Month = importJavaLib("java.time.Month")
month = LocalDate.now().plusDays(4).plusMonths(4).getMonth().getValue()
LocalDate.of(Int32(2021), Month.JANUARY, Int32(2))

HashMap = importJavaLib("java.util.HashMap")
jmap = HashMap.new(Int32(10), Float32(1.0))

HashSet = importJavaLib("java.util.HashSet")
set = HashSet.new()
set.add(LocalDate.now())
set.add(LocalDate.now().getMonth())

Arrays = importJavaLib("java.util.Arrays")
Arrays.copyOf([1,2,3], Int32(10))
Arrays.copyOf([LocalDate.now()], Int32(1)) # The Array for now stays as JObject

StringMod = importJavaLib("java.lang.String")
StringMod.new("123").concat("123").toString()

Boolean = importJavaLib("java.lang.Boolean")
Boolean.new(true)

# month_lib = @jimport "java.time.Month"
# month_class = classforname("java.time.Month")
# field_january = jcall(month_class, "getFields", Vector{JField}, ())[1]
# field_january(month_lib)


## FIXME: REMOVE, JUST FOR TESTING
lib = eval(Meta.parse("@jimport java.util.Arrays"))
methods = listmethods(lib, "copyOf")
generic_method = methods[9]
generic_type = getparametertypes(generic_method)[1]
