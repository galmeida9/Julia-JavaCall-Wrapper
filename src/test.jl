include("project.jl")
using Main.JavaImport

Math = importJavaLib("java.lang.Math")
Math.min(1, 2)
Math.min(1.3, 1.2)

Datetime = importJavaLib("java.time.LocalDate")
# dt = Datetime.now().plusDays(4).plusMonths(4)

# # HashMap = importJavaLib("java.util.HashMap")
# # jmap = HashMap.new()
# # #@new HashMap()

# Arrays = importJavaLib("java.util.Arrays")
# Arrays.copyOf([1,2,3], Int32(10))