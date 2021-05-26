using JavaCall
JavaCall.init(["-Xmx128M"])

# TODO: Improve naming of include
include("project_struct.jl")
using Main.project_struct

# Convert Java Objects to String with toString method 
Base.show(io::IO, obj::JavaObject) = print(io, jcall(obj,"toString", JString, ()))
Base.show(io::IO, obj::JavaValue) = print(io, jcall(getfield(obj, :ref),"toString", JString, ()))
Base.getproperty(jv::JavaValue, sym::Symbol) = getfield(getfield(jv, :methods), sym)(getfield(jv, :ref))

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

function isPrimitive(javaType)
    # TODO: What about arrays?
    return javaType in ["boolean", "char", "int", "long", "float", "double", "void"]
end

function getModule(name)
        try
            eval(Meta.parse("@which $name"))
        catch _
            eval(Meta.parse("module $name
                            using Main.project_struct, JavaCall
                            end"))
        end
end

isStatic(meth::JConstructor) = false
function isStatic(meth::Union{JMethod,JField})
    modifiers = JavaObject{Symbol("java.lang.reflect.Modifier")}

    mods = jcall(meth, "getModifiers", jint, ())
    jcall(modifiers, "isStatic", jboolean, (jint,), mods) != 0
end

function importJavaLib(javaLib)
    lib = eval(Meta.parse("@jimport $javaLib"))

    module_name = "$(replace(javaLib, '.' => '_'))"
    curr_module_static = getModule(module_name * "_static")
    curr_module_instance = getModule(module_name * "_instance")

    methods = listmethods(lib)
    for method in methods
        method_name = getname(method)
        java_return_type = getname(getreturntype(method))
        java_param_types = getparametertypes(method)

        julia_return_type = getTypeFromJava(java_return_type)

        variables = ""
        julia_param_types = ""
        julia_variables_with_types = variables
        if (length(java_param_types) != 0)
            # variables = join(map( type -> "convert(JObject, x$(type[1]))", enumerate(java_param_types)), ", ") * ","
            variables = join(map( type -> "x$(type[1])", enumerate(java_param_types)), ", ") * ","
            julia_param_types = map(type -> getTypeFromJava(getname(type)), java_param_types)
            # TODO: Remove the type from argument when the java type is Object
            # FIXME: GABI NÃO FAÇAS ISTO AINDA, HÁ O JPROXIES QUE SE CALHAR RESOLVE ISTO
            julia_variables_with_types = join(map( type -> "x$(type[1])::$(julia_param_types[type[1]])", enumerate(java_param_types)), ", ") * ","
            # julia_variables_with_types = join(map( type -> "x$(type[1])", enumerate(java_param_types)), ", ") * ","
            julia_param_types = join(julia_param_types, ", ") * ","
        end

        method_to_parse = ""
        if isStatic(method) && isPrimitive(java_return_type)
            method_to_parse = "function $method_name($julia_variables_with_types) jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables) end"
        else
            method_to_parse = "function $method_name($julia_variables_with_types) JavaValue(jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables), $curr_module_instance) end"
        end
        println(method_to_parse)
        println(isStatic(method))
        Base.eval(curr_module_static, Meta.parse(method_to_parse))

        instance_method = ""
        if isStatic(method)  && isPrimitive(java_return_type)
            instance_method = "$method_name = (instance) -> ($julia_variables_with_types) -> jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)"
        else
            instance_method = "$method_name = (instance) -> ($julia_variables_with_types) -> JavaValue(jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables), $curr_module_instance)"
        end
        Base.eval(curr_module_instance, Meta.parse(instance_method))
    end
    
    # Add empty constructor
    method_to_parse = "function new() JavaValue(($lib)(), $curr_module_instance) end"
    Base.eval(curr_module_static, Meta.parse(method_to_parse))

    curr_module_static
end

# Math = importJavaLib("java.lang.Math")
# Math.min(1, 2)
# Math.min(1.3, 1.2)

Datetime = importJavaLib("java.time.LocalDate")
dt = Datetime.now().plusDays(4).plusMonths(4)

# HashMap = importJavaLib("java.util.HashMap")

# TODOs:
# -[x] Add instance methods
# -[ ] Only declare static methods in module, if we can
# -[x] Only generate module if module hasn't been imported
# -[ ] Methods with arrays???
# -[x] Typify method arguments?
# -[ ] Import modules as needed, for example: Datetime.now().getMonth() returns a Month
# -[ ] Create new instance of objects

# Para saber os métodos dum módulo: names(Math, all=true)
