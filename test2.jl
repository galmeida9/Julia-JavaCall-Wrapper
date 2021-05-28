include("src/project.jl")
using Main.project

Math = importJavaLib("java.lang.Math")
Math.min(1, 2)
Math.min(1.3, 1.2)

Datetime = importJavaLib("java.time.LocalDate")
month = Datetime.now().plusDays(4).plusMonths(4).getMonth()

HashMap = importJavaLib("java.util.HashMap")
jmap = HashMap.new(Int32(10), Float32(1.0))
# # #@new HashMap()

# Arrays = importJavaLib("java.util.Arrays")
# Arrays.copyOf([1,2,3], Int32(10))