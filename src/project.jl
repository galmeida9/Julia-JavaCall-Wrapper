using JavaCall
JavaCall.init(["-Xmx128M"])

# Convert Java Objects to String with toString method 
Base.show(io::IO, obj::JavaObject) = print(io, jcall(obj,"toString", JString, ()))

function getTypeFromJava(javaType)
    primitiveTypes = ["boolean", "char", "int", "long", "float", "double"]

    if javaType == "void"
        return "Nothing"
    elseif javaType in primitiveTypes
        return "j" * javaType
    else 
        return "JavaObject{Symbol(\"$(javaType)\")}"
    end

    # TODO: verify for arrays
end


function importJavaLib(javaLib)
    lib = eval(Meta.parse("@jimport $javaLib"))

    # Define module
    methods_to_parse = Set()
    # TODO: Generate module only if it is the first time imported
    module_name = "$(replace(javaLib, '.' => '_'))$(rand(1:typemax(Int)))"
    curr_module = eval(Meta.parse("module $module_name using JavaCall end"))

    methods = listmethods(lib)
    for method in methods
        method_name = getname(method)
        java_return_type = getname(getreturntype(method))
        java_param_types = getparametertypes(method)

        julia_return_type = getTypeFromJava(java_return_type)

        variables = ""
        julia_param_types = ""
        if (length(java_param_types) != 0)
            variables = join(map( type -> "x$(type[1])", enumerate(java_param_types)), ", ") * ","
            julia_param_types = join(map(type -> getTypeFromJava(getname(type)), java_param_types), ", ") * ","
        end

        method_to_parse = "function $method_name($variables) jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables) end"
        Base.eval(curr_module, Meta.parse(method_to_parse))
    end
    
    return eval(Meta.parse(module_name))
end

Math = importJavaLib("java.lang.Math")
Math.ulp(1.2)

Datetime = importJavaLib("java.time.LocalDate")
Datetime.now()
# Datetime.plusDays(Datetime.now(), 5)

# plus_days(datetime, days) = jcall(datetime,"plusDays", jtLD, (jlong,), days)
# plus_days(Datetime.now(), 4)

# Datetime.metodo(x, y)

# a = Datetime.now()
# a.plus_days(4)

# TODOs:
# -[ ] Add instance methods
# -[ ] Only declare static methods in module, if we can
# -[ ] Only generate module if module hasn't been imported
# -[ ] Methods with arrays???

# Para saber os métodos dum módulo: names(Math, all=true)
