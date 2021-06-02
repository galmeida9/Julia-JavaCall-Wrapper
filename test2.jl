include("src/project.jl")
using Main.project, JavaCall

# Math = importJavaLib("java.lang.Math")
# Math.min(1, 2)
# Math.min(1.3, 1.2)
# Math.addExact(1,2)
# Math.addExact(Int32(4),Int32(8))

# LocalDate = importJavaLib("java.time.LocalDate")
# Month = importJavaLib("java.time.Month")
# month = LocalDate.now().plusDays(4).plusMonths(4).getMonth().getValue()
# LocalDate.of(Int32(2021), Month.JANUARY, Int32(2))
# LocalDate.now().equals(LocalDate.now())
# LocalDate.now().equals(LocalDate.now().plusDays(4))
# LocalDate.now().equals(1)
# LocalDate.now().equals(false)
# LocalDate.now().equals("123123123")

# HashMap = importJavaLib("java.util.HashMap")
# jmap = HashMap.new(Int32(10), Float32(1.0))

# HashSet = importJavaLib("java.util.HashSet")
# set = HashSet.new()
# set.add("123")
# set.add(LocalDate.now())
# set.add(LocalDate.now().getMonth())

# Arrays = importJavaLib("java.util.Arrays")
# Arrays.copyOf([1,2,3], Int32(10))
# Arrays.copyOf([LocalDate.now()], Int32(1)) # The Array for now stays as JObject

StringMod = importJavaLib("java.lang.String")
# a = StringMod.new("aaa")
# b = StringMod.new("123").concat("123").toString()
# a.concat(b) # TODO: This doesn't work right now

# Boolean = importJavaLib("java.lang.Boolean")
# Boolean.new(true)

# month_lib = @jimport "java.time.Month"
# month_class = classforname("java.time.Month")
# field_january = jcall(month_class, "getFields", Vector{JField}, ())[1]
# field_january(month_lib)


## FIXME: REMOVE, JUST FOR TESTING
# lib = eval(Meta.parse("@jimport java.util.Arrays"))
# methods = listmethods(lib, "copyOf")
# generic_method = methods[9]
# generic_type = getparametertypes(generic_method)[1]

JCharSequence = JavaObject{Symbol("java.lang.CharSequence")}
JLocalDate = JavaObject{Symbol("java.time.LocalDate")}

abstract type _JCharSequence end
abstract type _JString <: _JCharSequence end
# JCharSequence <: _JCharSequence
# JString <: _JString


s = JavaValue(JString(("2021-06-02")), java_lang_String_instance)
x1 = JString(("2021-06-02"))

function test(x::JavaValue{T}) where (T <: _JString)
  jcall(JLocalDate, "parse", JLocalDate, (JCharSequence,), x)
end

# a=JProxy(@jimport(java.util.ArrayList))()

# mutable struct JProxy{T, STATIC}
#   ptr::Ptr{Nothing}
#   info::JClassInfo
#   function JProxy{T, STATIC}(obj::JavaObject, info) where {T, STATIC}
#       finalizer(finalizeproxy, new{T, STATIC}(newglobalref(obj), info))
#   end
#   function JProxy{T, STATIC}(obj::PtrBox, info) where {T, STATIC}
#       finalizer(finalizeproxy, new{T, STATIC}(newglobalref(obj.ptr), info))
#   end
# end
