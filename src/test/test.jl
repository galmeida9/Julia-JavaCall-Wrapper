include("../main/project.jl")
using Main.JavaImport

Boolean   = importJavaLib("java.lang.Boolean")
StringMod = importJavaLib("java.lang.String")
Math      = importJavaLib("java.lang.Math")
LocalDate = importJavaLib("java.time.LocalDate")
Month     = importJavaLib("java.time.Month")
HashMap   = importJavaLib("java.util.HashMap")
HashSet   = importJavaLib("java.util.HashSet")
Arrays    = importJavaLib("java.util.Arrays")

# Assert that .equals() works
boolean_1 = Boolean.new(true)
@assert boolean_1.equals(boolean_1) == true

# Assert fields (and static methods) with primitives
@assert abs(Math.E - ℯ) <= 1e-10
@assert Math.min(1, 2) == 1
@assert Math.min(1.3, 1.2) == 1.2
@assert Math.addExact(1,2) == 3
@assert Math.addExact(Int32(4), Int32(8)) == Int32(12)

# Assert creation of objects and manipulation
str_test_1 = StringMod.new("test1")
str_test_2 = StringMod.new("test").concat("2").toString()
str_test_3 = StringMod.new("tes").concat("t3")
str_test_4 = str_test_1.concat(str_test_2)
@assert str_test_1.equals("test1") == true
@assert str_test_2.equals("test2") == true
@assert str_test_3.equals("test3") == true
@assert str_test_4.equals("test1test2") == true

# Assert import of libs on-the-fly
start_of_day = LocalDate.now().atStartOfDay() # Should import java.time.LocalDateTime, that was not imported
@assert typeof(start_of_day).parameters[1] == java_time_LocalDateTime

day_of_week = LocalDate.now().getDayOfWeek() # Should import java.time.DayOfWeek, that was not imported
@assert typeof(day_of_week).parameters[1] == java_time_DayOfWeek

date_chronology = LocalDate.now().getChronology() # Should import java.time.chrono.Chronology, that was not imported
@assert typeof(date_chronology).parameters[1] == java_time_chrono_Chronology

era_chronology = date_chronology.eras() # Should import java.util.List, that was not imported
@assert typeof(era_chronology).parameters[1] == java_util_List

# Assert non-primitive fields
@assert Month.JANUARY.getValue() == 1
@assert Month.FEBRUARY.getValue() == 2

# Assert instance methods with different class from the first
month = LocalDate.now().plusDays(4).plusMonths(4).getMonth().getValue()
date_1 = LocalDate.of(Int32(2021), Month.JANUARY, Int32(2))
@assert date_1.toString().equals("2021-01-02") == true
@assert LocalDate.now().equals(LocalDate.now()) == true
@assert LocalDate.now().equals(LocalDate.now().plusDays(4)) == false
@assert LocalDate.now().equals(1) == false
@assert LocalDate.now().equals(false) == false
@assert LocalDate.now().equals("123123123") == false

# Assert more constructors and instance methods with multiple classes
jmap = HashMap.new(Int32(10), Float32(1.0))
set = HashSet.new()
@assert set.add("123") == true
@assert set.add(LocalDate.now()) == true
@assert set.add(LocalDate.now().getMonth()) == true

# Assert non-primitive static methods
Arrays.copyOf([1,2,3], Int32(10))
nice_array = Arrays.copyOf([LocalDate.now(), set], Int32(2))
@assert nice_array[1].plusDays(2).plusMonths(1).getYear() == 2021

# Assert using subclasses in parameters
time_str = StringMod.new("2021-06-03")
parsed = LocalDate.parse(time_str) # Note: parse() receives a CharSequence and we send a String, that implements that
@assert parsed.toString().equals(time_str) == true

# Assert that we can receive exceptions
try
  LocalDate.now().atTime(Int32(1), Int32(-1))
  @assert false
catch e
  # Success, we catched it
end
