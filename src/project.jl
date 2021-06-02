module project_struct
    using JavaCall

    struct JavaValue{T<:JavaObject}
        ref::T
        methods::Module
    end

    Base.show(io::IO, obj::JavaValue) = print(io, jcall(getfield(obj, :ref), "toString", JString, ()))
    Base.getproperty(jv::JavaValue, sym::Symbol) = getfield(getfield(jv, :methods), sym)(getfield(jv, :ref))

    export JavaValue
end

module project

    # IMPORTS #
    # TODO: Improve naming of project_struct
    using JavaCall, Main.project_struct
    
    # Initialize JVM if needed
    if (!JavaCall.isloaded())
        JavaCall.init(["-Xmx128M"])
    end

    # CONSTANTS #
    const global MODULE_STATIC_NAME = "_static"
    const global MODULE_INSTANCE_NAME = "_instance"

    # Convert Java Objects to String with toString method 
    Base.show(io::IO, obj::JavaObject) = print(io, jcall(obj, "toString", JString, ()))
    Base.show(io::IO, obj::jboolean) = print(io, Bool(obj))

    function getTypeFromJava(javaType, is_not_julia_parameter=true)
        primitiveTypes = ["char", "int", "long", "float", "double"]

        if javaType == "void"
            "Nothing"
        # FIXME: Now this prevents JavaValue of Strings...
        elseif javaType == "java.lang.String" && !is_not_julia_parameter
            "String"
        elseif javaType == "boolean" && !is_not_julia_parameter
            "Bool"
        elseif javaType == "boolean" && is_not_julia_parameter
            "UInt8"
        elseif javaType in primitiveTypes
            "j" * javaType
        elseif occursin("[]", javaType)
            reference_type = getTypeFromJava(javaType[begin:end - 2], is_not_julia_parameter)
            "Vector{$reference_type}"
        else 
            is_not_julia_parameter ? "JavaObject{Symbol(\"$(javaType)\")}" : "JavaValue{JavaObject{Symbol(\"$(javaType)\")}}"
        end
    end

    function isPrimitive(javaType)
        javaType in ["boolean", "char", "int", "long", "float", "double", "void"] || occursin("[]", javaType)
    end

    function isArrayOfJavaObject(javaType)
        getname(javaType)  == "java.lang.Object[]"
    end

    function isJavaObject(javaType)
        getname(javaType)  == "java.lang.Object"
    end

    # Returns an array, where the first element is a boolean representing if a module is new
    # and the second element is the actual module
    function getModule(name)
        try
            [false, Base.eval(Main, Meta.parse("$name"))]
        catch _
            [
                true,
                Base.eval(
                    Main,
                    Meta.parse("module $name
                                using Main.project_struct, Main.project, JavaCall
                                end")
                )
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

    function getVariablesForFunction(java_param_types)
        # variables = join(map( type -> isJavaObject(type[2]) ? "convert(JObject, eval(Meta.parse(getTypeFromJava(x$(type[1])))))" : "x$(type[1])", enumerate(java_param_types)), ", ") * ","
        # variables = join(map(type -> "x$(type[1])", enumerate(java_param_types)), ", ") * ","
        join(
            map(
                # [Datetime.now()]
                type -> begin
                    name_type = getTypeFromJava(getname(type[2]), false)
                    # Vector{JavaValue} -> :), Vector{Vector{JavaValue}} -> :(
                    if occursin("Vector", name_type) && occursin("JavaValue", name_type)
                        "map(el -> getfield(el, :ref), x$(type[1]))"
                    elseif occursin("JavaValue", name_type)
                        "getfield(x$(type[1]), :ref)"
                    else
                        "x$(type[1])"
                    end
                end,
                enumerate(java_param_types)
            )
            , ", "
        ) * ","
    end

    function getJuliaParamTypesForFunction(java_param_types)
        join(map(type -> getTypeFromJava(getname(type)), java_param_types), ", ") * ","
    end

    function getJuliaVariablesWithTypes(java_param_types)
        params = "("
        params_jobject = "("
        where_tag = ""

        for (index, type) in enumerate(java_param_types)
            if isJavaObject(type)
                params         = params * "x$(index)::JavaValue{T$(index)}, "
                params_jobject = params_jobject * "x$(index)::$( getTypeFromJava(getname(type)) ), "
                where_tag      = where_tag * "T$(index)<:JavaObject, "
            elseif isArrayOfJavaObject(type)
                params         = params * "x$(index)::Vector{JavaValue{T$(index)}}, "
                params_jobject = params_jobject * "x$(index)::Vector{$( getTypeFromJava(getname(type)) )}, "
                where_tag      = where_tag * "T$(index)<:JavaObject, "
            else
                params         = params * "x$(index)::$( getTypeFromJava(getname(type), false) ), "
                params_jobject = params_jobject * "x$(index)::$( getTypeFromJava(getname(type), false) ), "
            end
        end

        params         = params * ")"
        params_jobject = params_jobject * ")"

        if where_tag != ""
            where_tag = " where {" * where_tag * "}"
            return [params * where_tag, params_jobject]
        else
            return [params, ""]
        end

        # TODO: Inheritance of types to allow put(x1::Object) to use any type
        # julia_variables_with_types = join(
        #     map(type -> "x$(type[1])::$(julia_param_types[type[1]])", enumerate(java_param_types)), ", "
        # ) * ","

        # julia_variables_with_types = join(map( type -> "x$(type[1])", enumerate(java_param_types)), ", ") * ","

    end

    function createStaticPrimitiveFunction(method_name, julia_var_w_types, lib, julia_return_type, julia_param_types, variables)
        "function $method_name$julia_var_w_types
            jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
        end"
    end

    function createStaticNonPrimitiveFunction(method_name, julia_var_w_types, java_return_type, lib, julia_return_type, julia_param_types, variables)
        "function $method_name$julia_var_w_types
            curr_module = getInstanceModule(\"$java_return_type\")
            JavaValue{$julia_return_type}(jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables), curr_module) 
        end"
    end

    function createInstancePrimitiveFunction(method_name, julia_var_w_types, lib, julia_return_type, julia_param_types, variables)
        "$method_name = (instance) -> 
            function $(julia_var_w_types) 
                jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
            end"
    end

    function createInstanceNonPrimitiveFunction(method_name, julia_var_w_types, java_return_type, lib, julia_return_type, julia_param_types, variables)
        "$method_name = (instance) ->
            function $(julia_var_w_types)
                curr_module = getInstanceModule(\"$java_return_type\")
                JavaValue{$julia_return_type}(jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables), curr_module)
            end"
    end

    function addConstantsAndFields(javaLib, lib, curr_module_static)
        cls = classforname(javaLib)
        fields = jcall(cls, "getFields", Vector{JField}, ())

        for (index, field) in enumerate(fields)
            field_name = getname(field)
            java_field_type = getname(jcall(field, "getType", JClass))

            if isPrimitive(java_field_type)
                field_to_parse = "$field_name = $(field(lib))"
                Base.eval(curr_module_static, Meta.parse(field_to_parse))
            else
            # TODO: Improve getting the fields without calling JavaCall and getting always an array
                field_to_parse =
                "$field_name = 
                (function() 
                    JavaValue(
                    (function()
                        cls = classforname(\"$javaLib\")
                        jcall(cls, \"getFields\", Vector{JField})[$index]($lib)
                    end)(),
                    getInstanceModule(\"$java_field_type\")
                    )
                end)()"
                Base.eval(curr_module_static, Meta.parse(field_to_parse))
            end
        end
    end

    function addConstructors(javaLib, lib, curr_module_static, curr_module_instance)
        cls = classforname(javaLib)
        constructors = jcall(cls, "getConstructors", Vector{JConstructor}, ())

        for constructor in constructors
            java_param_types = getparametertypes(constructor)
                
            variables = ""
            julia_param_types = ""
            julia_variables_with_types = "()"
            if (length(java_param_types) != 0)
                variables = getVariablesForFunction(java_param_types)
                julia_variables_with_types, _ = getJuliaVariablesWithTypes(java_param_types)
                julia_param_types = getJuliaParamTypesForFunction(java_param_types)
            end

            return_type = getTypeFromJava(javaLib, false)
            method_to_parse = ""
            if return_type == "String"
                method_to_parse = "function new$julia_variables_with_types
                                        JavaValue(JString(($lib)(($julia_param_types), $variables)), $curr_module_instance)
                                    end"
            else occursin("JavaValue", return_type)
                method_to_parse = "function new$julia_variables_with_types
                                        JavaValue(($lib)(($julia_param_types), $variables), $curr_module_instance)
                                    end"
            end
            Base.eval(curr_module_static, Meta.parse(method_to_parse))
        end
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
            julia_var_w_types = ["()", ""]

            if length(java_param_types) != 0
                variables = getVariablesForFunction(java_param_types)
                julia_param_types = getJuliaParamTypesForFunction(java_param_types)
                julia_var_w_types = getJuliaVariablesWithTypes(java_param_types)
            end

            if isStatic(method)
                for var_types in julia_var_w_types
                    if var_types != ""
                        Base.eval(curr_module_static, Meta.parse(
                            isPrimitive(java_return_type) ? 
                                createStaticPrimitiveFunction(method_name, var_types, lib, julia_return_type, julia_param_types, variables) :
                                createStaticNonPrimitiveFunction(method_name, var_types, java_return_type, lib, julia_return_type, julia_param_types, variables)
                        ))
                    end
                end
            else
                # TODO: this should work
                # for var_types in julia_var_w_types
                #     if var_types != ""
                #         Base.eval(curr_module_instance, Meta.parse(
                #             isPrimitive(java_return_type) ? 
                #                 createInstancePrimitiveFunction(method_name, var_types, lib, julia_return_type, julia_param_types, variables) :
                #                 createInstanceNonPrimitiveFunction(method_name, var_types, java_return_type, lib, julia_return_type, julia_param_types, variables)
                #         ))
                #     end
                # end
                Base.eval(curr_module_instance, Meta.parse(
                    isPrimitive(java_return_type) ? 
                        createInstancePrimitiveFunction(method_name, julia_var_w_types[1], lib, julia_return_type, julia_param_types, variables) :
                        createInstanceNonPrimitiveFunction(method_name, julia_var_w_types[1], java_return_type, lib, julia_return_type, julia_param_types, variables)
                ))
            end
        end
        
        if (javaLib != "java.lang.Class")
            addConstructors(javaLib, lib, curr_module_static, curr_module_instance)
            addConstantsAndFields(javaLib, lib, curr_module_static)
        end

        curr_module_static
    end

    export getInstanceModule, importJavaLib, JavaValue # FIXME: Remove JavaValue?
end

# function JFieldInfo(field::JField)
#     fcl = jcall(field, "getType", JClass, ())
#     typ = juliaTypeFor(legalClassName(fcl))
#     static = isStatic(field)
#     cls = jcall(field, "getDeclaringClass", JClass, ())
#     id = fieldId(getname(field), JavaObject{Symbol(legalClassName(fcl))}, static, field, cls)
#     info = get(typeInfo, legalClassName(fcl), genericFieldInfo)
#     JFieldInfo{info.convertType}(field, info, static, id, cls)
# end

# Para obter o valor do field (i.e.: Math.PI)
# math_class = classforname("java.lang.Math")
# field_pi = jcall(math_class, "getFields", Vector{JField}, ())[2]
# field_pi(math_lib)

# Para saber os métodos dum módulo: names(Math, all=true)


# a = Module.get_array() => HashMap[]
# Vector{JavaObject{HashMap}}
# a[0].put(...)