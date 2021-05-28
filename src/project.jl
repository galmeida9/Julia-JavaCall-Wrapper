module project_struct
    using JavaCall
    struct JavaValue
        ref::JavaObject
        methods::Module
    end
    Base.show(io::IO, obj::JavaValue) = print(io, jcall(getfield(obj, :ref),"toString", JString, ()))
    Base.getproperty(jv::JavaValue, sym::Symbol) = getfield(getfield(jv, :methods), sym)(getfield(jv, :ref))
    export JavaValue
end

module project
    # TODO: Improve naming of include

    # IMPORTS #
    # include("project_struct.jl")
    using JavaCall, Main.project_struct
    
    # Initialize JVM if needed
    if (!JavaCall.isloaded())
        JavaCall.init(["-Xmx128M"])
    end

    # CONSTANTS #
    const global MODULE_STATIC_NAME = "_static"
    const global MODULE_INSTANCE_NAME = "_instance"

    # Convert Java Objects to String with toString method 
    Base.show(io::IO, obj::JavaObject) = print(io, jcall(obj,"toString", JString, ()))

    function getTypeFromJava(javaType)
        primitiveTypes = ["boolean", "char", "int", "long", "float", "double"]

        if javaType == "void"
            return "Nothing"
        elseif javaType in primitiveTypes
            return "j" * javaType
        elseif occursin("[]", javaType)
            reference_type = getTypeFromJava(javaType[begin:end-2])
            return "Vector{$reference_type}"
        else 
            return "JavaObject{Symbol(\"$(javaType)\")}"
        end
    end

    function isPrimitive(javaType)
        return javaType in ["boolean", "char", "int", "long", "float", "double", "void"] || occursin("[]", javaType)
    end

    function isJavaObject(javaType)
        println(javaType)
        println(getname(javaType))
        return occursin("java.lang.Object", getname(javaType))
    end

    # Returns an array, where the first element is a boolean representing if a module is new
    # and the second element is the actual module
    function getModule(name)
            try
                Base.eval(Main, Meta.parse("@which $name"))
                [false, Base.eval(Main, Meta.parse("$name"))]
            catch _
                [
                    true,
                    Base.eval(Main, Meta.parse("module $name
                                using Main.project_struct, Main.project, JavaCall
                                end"))
                ]
            end
    end

    function isStatic(meth::JMethod)
        modifiersLib = @jimport java.lang.reflect.Modifier
        modifiers = jcall(meth, "getModifiers", jint, ())
        isMethodStatic = jcall(modifiersLib, "isStatic", jboolean, (jint,), modifiers)
        isMethodStatic != 0
    end

    function getInstanceModule(java_return_type)
        module_name = replace(java_return_type, '.' => '_')
        isNewModule, curr_module_instance = getModule(module_name * MODULE_INSTANCE_NAME)

        if (isNewModule)
            importJavaLib(java_return_type)
        end

        curr_module_instance
    end

    function importJavaLib(javaLib)
        lib = eval(Meta.parse("@jimport $javaLib"))

        module_name = replace(javaLib, '.' => '_')
        isNewModule, curr_module_static = getModule(module_name * MODULE_STATIC_NAME)
        _, curr_module_instance = getModule(module_name * MODULE_INSTANCE_NAME)

        if (!isNewModule) return curr_module_static end

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
                # variables = join(map( type -> isJavaObject(type[2]) ? "convert(JObject, eval(Meta.parse(getTypeFromJava(x$(type[1])))))" : "x$(type[1])", enumerate(java_param_types)), ", ") * ","
                variables = join(map( type -> "x$(type[1])", enumerate(java_param_types)), ", ") * ","
                julia_param_types = map(type -> getTypeFromJava(getname(type)), java_param_types)
                # TODO: Inheritance of types to allow put(x1::Object) to use JString i.e.
                julia_variables_with_types = join(map( type -> "x$(type[1])::$(julia_param_types[type[1]])", enumerate(java_param_types)), ", ") * ","
                # julia_variables_with_types = join(map( type -> "x$(type[1])", enumerate(java_param_types)), ", ") * ","
                julia_param_types = join(julia_param_types, ", ") * ","
            end

            method_to_parse = ""
            if isStatic(method)
                if isPrimitive(java_return_type)
                    method_to_parse = "function $method_name($julia_variables_with_types) jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables) end"
                else
                    method_to_parse = "function $method_name($julia_variables_with_types)
                                            curr_module = getInstanceModule(\"$java_return_type\")
                                            JavaValue(jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables), curr_module) 
                                        end"
                end
                Base.eval(curr_module_static, Meta.parse(method_to_parse))
            else
                instance_method = ""
                if isPrimitive(java_return_type)
                    instance_method = "$method_name = (instance) -> ($julia_variables_with_types) -> jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)"
                else
                    instance_method = "$method_name = (instance) ->
                                        function ($julia_variables_with_types)
                                            curr_module = getInstanceModule(\"$java_return_type\")
                                            JavaValue(jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables), curr_module)
                                        end"
                                        # curr_module = getInstanceModule(\"$java_return_type\")
                end
                Base.eval(curr_module_instance, Meta.parse(instance_method))
            end
        end
        
        # Add empty constructor
        # TODO: Add all the constructors
        method_to_parse = "function new() JavaValue(($lib)(), $curr_module_instance) end"
        Base.eval(curr_module_static, Meta.parse(method_to_parse))

        curr_module_static
    end

    export getInstanceModule, importJavaLib
end

# Math = importJavaLib("java.lang.Math")
# Math.min(1, 2)
# Math.min(1.3, 1.2)

# Datetime = importJavaLib("java.time.LocalDate")
# dt = Datetime.now().plusDays(4).plusMonths(4)

# HashMap = importJavaLib("java.util.HashMap")
# jmap = HashMap.new()
# #@new HashMap()

# Arrays = importJavaLib("java.util.Arrays")
# Arrays.copyOf([1,2,3], Int32(10))

# gurl = jnu((JString,), "http://www.google.com")
# lib((tuple with types,), variables)

# h = HashMap.new() -> HashMap
# h.getClass() -> Class (h.getClass(), Class_module)
# a.getDeclaredMethods()


# m = Datetime.now().getMonth() -> Month (m, module_Month) typeof(m) -> JavaObject{java.time.Month}
# m.getDayOfMonth()

# TODOs:
# -[X] Add instance methods
# -[X] Only declare static methods in module, if we can
# -[X] Only generate module if module hasn't been imported
# -[X] Do not reimport a module
# -[X] Methods with arrays???
# -[X] Typify method arguments?
# -[ ] Allow JObject methods to use JString i.e.
# -[X] Import modules as needed, for example: Datetime.now().getMonth() returns a Month
# -[ ] Get all constructors
# -[ ] Convert jboolean to Bool
# -[ ] getfields ao importar
# -[X] include path issue

# function JFieldInfo(field::JField)
#     fcl = jcall(field, "getType", JClass, ())
#     typ = juliaTypeFor(legalClassName(fcl))
#     static = isStatic(field)
#     cls = jcall(field, "getDeclaringClass", JClass, ())
#     id = fieldId(getname(field), JavaObject{Symbol(legalClassName(fcl))}, static, field, cls)
#     info = get(typeInfo, legalClassName(fcl), genericFieldInfo)
#     JFieldInfo{info.convertType}(field, info, static, id, cls)
# end

# Para saber os métodos dum módulo: names(Math, all=true)
