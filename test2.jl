include("src/project.jl")
using Main.project, JavaCall

math_lib = @jimport "java.lang.Math"
Math = importJavaLib("java.lang.Math")
Math.min(1, 2)
Math.min(1.3, 1.2)

Datetime = importJavaLib("java.time.LocalDate")
Month = importJavaLib("java.time.Month")
month = Datetime.now().plusDays(4).plusMonths(4).getMonth().getValue()

HashMap = importJavaLib("java.util.HashMap")
jmap = HashMap.new(Int32(10), Float32(1.0))
# @new HashMap()

HashSet = importJavaLib("java.util.HashSet")
set = HashSet.new()

Arrays = importJavaLib("java.util.Arrays")
Arrays.copyOf([1,2,3], Int32(10))
# Arrays.copyOf([Datetime.now()]) -> Not working, needs inheritance from Object

StringMod = importJavaLib("java.lang.String")
StringMod.new("123").concat("123").toString()

# month_lib = @jimport "java.time.Month"
# month_class = classforname("java.time.Month")
# field_january = jcall(month_class, "getFields", Vector{JField}, ())[1]
# field_january(month_lib)

### é isto crl
function test(x::T) where {T<:Any}
  println(x)
end
