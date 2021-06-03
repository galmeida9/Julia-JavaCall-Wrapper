include("src/project.jl")
using Main.JavaImport, JavaCall

Math = importJavaLib("java.lang.Math")
Math.PI
Math.min(1, 2)
Math.min(1.3, 1.2)
Math.addExact(1,2)
Math.addExact(Int32(4),Int32(8))

LocalDate = importJavaLib("java.time.LocalDate")
Month = importJavaLib("java.time.Month")
Month.JANUARY.getValue()
month = LocalDate.now().plusDays(4).plusMonths(4).getMonth().getValue()
LocalDate.of(Int32(2021), Month.JANUARY, Int32(2))
LocalDate.now().equals(LocalDate.now())
LocalDate.now().equals(LocalDate.now().plusDays(4))
LocalDate.now().equals(1)
LocalDate.now().equals(false)
LocalDate.now().equals("123123123")

HashMap = importJavaLib("java.util.HashMap")
jmap = HashMap.new(Int32(10), Float32(1.0))

HashSet = importJavaLib("java.util.HashSet")
set = HashSet.new()
set.add("123")
set.add(LocalDate.now())
set.add(LocalDate.now().getMonth())

Arrays = importJavaLib("java.util.Arrays")
Arrays.copyOf([1,2,3], Int32(10))
nice_array = Arrays.copyOf([LocalDate.now(), set], Int32(2))
nice_array[1].plusDays(2).plusMonths(4).getYear()


StringMod = importJavaLib("java.lang.String")
a = StringMod.new("aaa")
b = StringMod.new("123").concat("123").toString()
c = StringMod.new("123").concat("123")
a.concat(b)

timeStr = StringMod.new("2021-06-03")
LocalDate.parse(timeStr)

Boolean = importJavaLib("java.lang.Boolean")
Boolean.new(true)

