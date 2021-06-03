module project_struct
    using JavaCall

    struct JavaValue{T1}
        ref::JavaObject
        methods::Module

        function JavaValue{T}(ref, methods) where T
            new{T}(ref, methods)
        end
    end

    function _getRef(jv::JavaValue)
        getfield(jv, :ref)
    end

    function _getMethods(jv::JavaValue)
        getfield(jv, :methods)
    end

    Base.show(io::IO, obj::JavaValue) = print(io, jcall(_getRef(obj), "toString", JString, ()))
    Base.getproperty(jv::JavaValue, sym::Symbol) = getfield(_getMethods(jv), sym)(_getRef(jv))

    export JavaValue, _getRef, _getMethods, java_lang_Object
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
    const global MODULE_STATIC_NAME   = "_static"
    const global MODULE_INSTANCE_NAME = "_instance"

    # Convert Java Objects to String with toString method 
    Base.show(io::IO, obj::JavaObject) = begin
        if isnull(obj)
            print(io, "null")
        else
            print(io, jcall(obj, "toString", JString, ()))
        end
    end
    Base.show(io::IO, obj::jboolean) = print(io, Bool(obj))

    function getTypeFromJava(javaType, is_not_julia_parameter=true)
        primitiveTypes = ["char", "int", "long", "float", "double"]

        if javaType == "void"
            "Nothing"
        elseif javaType == "java.lang.String" && !is_not_julia_parameter
            "String"
        elseif javaType == "boolean" && !is_not_julia_parameter
            "Bool"
        elseif javaType == "boolean" && is_not_julia_parameter
            "UInt8"
        elseif javaType == "byte"
            "UInt8"
        elseif javaType == "short"
            "Int16"
        elseif javaType in primitiveTypes
            "j" * javaType
        elseif occursin("[]", javaType)
            reference_type = getTypeFromJava(javaType[begin:end - 2], is_not_julia_parameter)
            "Vector{$reference_type}"
        else 
            is_not_julia_parameter ? "JavaObject{Symbol(\"$(javaType)\")}" : "JavaValue{JavaObject{Symbol(\"$(javaType)\")}}"
        end
    end

    function getTypesConvertion(value)
        # Get generic type, without parametric types
        generic_type(::Type{T}) where T = eval(nameof(T))
        type = generic_type(typeof(value))

        # TODO: Add remainining types
        types_convertion = Dict(
            Bool        => (x) -> jcall(JavaObject{Symbol("java.lang.Boolean")}, "valueOf", JavaObject{Symbol("java.lang.Boolean")}, (JString,), String(Symbol(x))),
            String      => (x) -> convert(JString, x),
            Char        => (x) -> jcall(JavaObject{Symbol("java.lang.String")}, "valueOf", JavaObject{Symbol("java.lang.String")}, (jchar,), x),
            Int64       => (x) -> convert(JavaObject{Symbol("java.lang.Long")}, x),
            Int32       => (x) -> convert(JavaObject{Symbol("java.lang.Integer")}, x),
            Float64     => (x) -> convert(JavaObject{Symbol("java.lang.Double")}, x),
            Float32     => (x) -> convert(JavaObject{Symbol("java.lang.Float")}, x),
            JavaValue   => (x) -> _getRef(x),
            Vector      => (x) -> map(el -> getTypesConvertion(el), x),
            Array       => (x) -> map(el -> getTypesConvertion(el), x),
        )

        if type in keys(types_convertion)
            types_convertion[type](value)
        else
            value
        end
    end

    function getReturnValue(ref)
        if typeof(ref) == String
            ref = JString(ref)
        end
        ref
    end

    function isPrimitive(javaType)
        javaType in ["boolean", "char", "int", "long", "float", "double", "void", "byte", "short"] || occursin("[]", javaType)
    end

    function isArrayOfJavaObject(javaType)
        getname(javaType)  == "java.lang.Object[]"
    end

    function isJavaObject(javaType)
        getname(javaType)  == "java.lang.Object"
    end

    function isStringType(javaType)
        getname(javaType)  == "java.lang.String"
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
                                using Main, Main.project_struct, Main.project, JavaCall
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

    function isInterface(class_name)
        if isPrimitive(class_name)
            return false
        end

        is_interface = jcall(classforname(class_name), "isInterface", jboolean, ())
        is_interface == 1
    end

    function getInstanceModule(java_return_type)
        module_name = replace(java_return_type, '.' => '_')
        isNewModule, curr_module_instance = getModule(module_name * MODULE_INSTANCE_NAME)

        if (isNewModule)
            importJavaLib(java_return_type)
        end

        curr_module_instance
    end

    function getAbstractTypeName(given_type_name)
        curr_type_name = replace(given_type_name, '.' => '_')

        # Try to find if exists at first
        # If not, create the type and try to get the super class recursively
        try
            Base.eval(Main, Meta.parse("$curr_type_name"))
            return "Main.$curr_type_name"
        catch
        end


        if given_type_name == "java.lang.Object"
            Base.eval(Main, Meta.parse("abstract type $curr_type_name end"))
            return "Main.$curr_type_name"
        end

        if isInterface(given_type_name)
            try
                Base.eval(Main, Meta.parse("$curr_type_name"))
            catch
                Base.eval(Main, Meta.parse("abstract type $curr_type_name end"))
            end
            return "Main.$curr_type_name"
        end

        super_class = getname(jcall(classforname(given_type_name), "getSuperclass", JClass, ()))
        super_class_name = getAbstractTypeName(super_class)

        # Define type
        Base.eval(Main, Meta.parse("abstract type $curr_type_name <: $super_class_name end"))
        
        "Main.$curr_type_name"
    end

    function getVariablesForFunction(params)
        join(
            map(type -> "x$(type[1])", enumerate(params) )
            , ", "
        ) * ", "
    end

    function getJuliaParamTypesForFunction(java_param_types)
        join(map(type -> isJavaObject(type[2]) ? "JObject" : getTypeFromJava(getname(type[2])), enumerate(java_param_types)), ", ") * ","
    end

    function getJuliaVariablesWithTypes(java_param_types, instance = false)
        params = "("
        params_javaValue = "("
        where_tag_jv = ""
        where_tag = ""

        if instance
            params              = params            * "instance, "
            params_javaValue    = params_javaValue  * "instance, "
        end

        # new Hashset().add(e) => classes (para o JObject)
        # add(e::JavaValue{T}) where T <: java_lang_Object
        # add(e::T) where T <: Any

        # HashSet(AbstractCollection c) => classes
        # new(x1::JavaValue{T}) where T <: java_util_AbstractCollection

        # LocalDate.parse(CharSequence s) => interfaces
        # parse(x1::JavaValue{T1}) where T1 <: java_lang_CharSequence
        # parse(x1::JavaValue{T1}) where T1 <: Any

        # Math.min(int a, int b) => primitivas
        # min(a::Int32, b::Int32)

        # StringMod.new("123").concat(String a).toString() => String
        # concat(x1::JavaValue{T1}) where (T1 <: java_lang_String)
        # concat(x1::String)

        # Any => jcall(lib, "...", ..., (T, ))
        # Any => jcall(lib, "...", ..., (Vector{T}, ))
        # Any => jcall(lib, "...", ..., (T, ))

        # TODO: improve code
        for (index, type) in enumerate(java_param_types)
            # TODO: arrays of classes not JObject
            if isJavaObject(type)
                params              = params            * "x$(index)::T$(index), "
                where_tag           = where_tag         * "T$(index)<:Any, "

                params_javaValue    = params_javaValue  * "x$(index)::JavaValue{T$(index)}, "
                where_tag_jv        = where_tag_jv      * "T$(index)<:Main.java_lang_Object, "
            elseif isArrayOfJavaObject(type)        
                params_javaValue    = params_javaValue  * "x$(index)::Vector{JavaValue{T$(index)}}, "
                where_tag_jv        = where_tag_jv      * "T$(index)<:Main.java_lang_Object, "

                params              = params            * "x$(index)::Vector{T$index}, "
                where_tag           = where_tag         * "T$(index)<:Any, "
            elseif isInterface(getname(type))
                params              = params            * "x$(index)::JavaValue{T$(index)}, "
                where_tag           = where_tag         * "T$(index)<:Any, "

                params_javaValue    = params_javaValue  * "x$(index)::JavaValue{T$(index)}, "
                where_tag_jv        = where_tag_jv      * "T$(index)<:$(getAbstractTypeName(getname(type))), "
            elseif isStringType(type)
                params              = params            * "x$(index)::String, "

                params_javaValue    = params_javaValue  * "x$(index)::JavaValue{T$(index)}, "
                where_tag_jv        = where_tag_jv      * "T$(index)<:$(getAbstractTypeName(getname(type))), "
            elseif !isPrimitive(getname(type))
                params_javaValue    = params_javaValue  * "x$(index)::JavaValue{T$(index)}, "
                where_tag_jv        = where_tag_jv      * "T$(index)<:$(getAbstractTypeName(getname(type))), "

                params              = params_javaValue
                where_tag           = where_tag_jv
            else
                params              = params            * "x$(index)::$( getTypeFromJava(getname(type), false) ), "
                params_javaValue    = params_javaValue  * "x$(index)::$( getTypeFromJava(getname(type), false) ), "
            end
        end

        params           = params * ")"
        params_javaValue = params_javaValue * ")"
        all_params = []

        # TODO: Improve ifs
        if where_tag != ""
            where_tag = " where {" * where_tag * "}"
            push!(all_params, params * where_tag)
        end

        if where_tag_jv != ""
            where_tag_jv = " where {" * where_tag_jv * "}"
            push!(all_params, params_javaValue * where_tag_jv)
        end

        if params != "(" && where_tag == ""
            push!(all_params, params)
        end

        if params_javaValue != "(" && where_tag_jv == ""
            push!(all_params, params_javaValue)
        end

        all_params
    end

    function getAllVariablesConverted(variables)
        curr_variables = split(variables, ", ", keepempty=false)
        res = ""
        for var in curr_variables
            res *= "$var = getTypesConvertion($var)\n"
        end
        res
    end

    function createStaticPrimitiveFunction(method_name, julia_var_w_types, lib, julia_return_type, julia_param_types, variables)
        "function $method_name$julia_var_w_types
            $(getAllVariablesConverted(variables))
            jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
        end"
    end

    function createStaticNonPrimitiveFunction(method_name, julia_var_w_types, java_return_type, jv_type_name, lib, julia_return_type, julia_param_types, variables)
        "function $method_name$julia_var_w_types
            $(getAllVariablesConverted(variables))
            curr_module = getInstanceModule(\"$java_return_type\")
            return_value = jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
            return_value = getReturnValue(return_value)
            JavaValue{$jv_type_name}(return_value, curr_module) 
        end"
    end

    function createInstancePrimitiveFunction(method_name, julia_var_w_types, julia_return_type, julia_param_types, variables)
        "function _$method_name$julia_var_w_types
            $(getAllVariablesConverted(variables))         
            jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
        end"
    end

    function createInstanceNonPrimitiveFunction(method_name, julia_var_w_types, java_return_type, jv_type_name, julia_return_type, julia_param_types, variables)
        "function _$method_name$julia_var_w_types
            $(getAllVariablesConverted(variables))
            curr_module = getInstanceModule(\"$java_return_type\")
            return_value = jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
            return_value = getReturnValue(return_value)
            JavaValue{$jv_type_name}(return_value, curr_module)
        end"
    end

    function createMainInstanceFunction(method_name)
        "function $method_name(instance)
            function (args...)
                _$method_name(instance, args...)
            end
        end"
    end

    function addConstantsAndFields(javaLib, jv_type_name, lib, curr_module_static)
        cls = classforname(javaLib)
        fields = jcall(cls, "getFields", Vector{JField}, ())

        for field in fields
            field_name = getname(field)
            java_field_type = getname(jcall(field, "getType", JClass))

            if isPrimitive(java_field_type)
                field_to_parse = "$field_name = $(field(lib))"
                Base.eval(curr_module_static, Meta.parse(field_to_parse))
            else
                # FIXME: Set correct JavaValue type
                field_to_parse =
                "$field_name = 
                (function() 
                    JavaValue{$jv_type_name}(
                        (function()
                            cls = classforname(\"$javaLib\")
                            jcall(cls, \"getField\", JField, (JString, ), \"$field_name\")($lib)
                        end)(),
                        getInstanceModule(\"$java_field_type\")
                    )
                end)()"
                Base.eval(curr_module_static, Meta.parse(field_to_parse))
            end
        end
    end

    function addConstructors(javaLib, jv_type_name, lib, curr_module_static, curr_module_instance)
        cls = classforname(javaLib)
        constructors = jcall(cls, "getConstructors", Vector{JConstructor}, ())

        for constructor in constructors
            java_param_types = getparametertypes(constructor)
                
            variables = ""
            julia_param_types = ""
            julia_variables_with_types = ["()"]
            if (length(java_param_types) != 0)
                variables = getVariablesForFunction(java_param_types)
                julia_variables_with_types = getJuliaVariablesWithTypes(java_param_types)
                julia_param_types = getJuliaParamTypesForFunction(java_param_types)
            end

            return_type = getTypeFromJava(javaLib, false)
            method_to_parse = ""
            if return_type == "String"
                for var_types in julia_variables_with_types
                    method_to_parse = "function new$var_types
                                            $(getAllVariablesConverted(variables))
                                            JavaValue{$jv_type_name}(JString(($lib)(($julia_param_types), $variables)), $curr_module_instance)
                                        end"
                    Base.eval(curr_module_static, Meta.parse(method_to_parse))
                end
            else occursin("JavaValue", return_type)
                for var_types in julia_variables_with_types
                    method_to_parse = "function new$var_types
                                            $(getAllVariablesConverted(variables))
                                            JavaValue{$jv_type_name}(($lib)(($julia_param_types), $variables), $curr_module_instance)
                                        end"
                    Base.eval(curr_module_static, Meta.parse(method_to_parse))
                end
            end
        end
    end

    function importJavaLib(javaLib)
        lib = eval(Meta.parse("@jimport $javaLib"))

        module_name = replace(javaLib, '.' => '_')
        isNewModule, curr_module_static = getModule(module_name * MODULE_STATIC_NAME)
        _, curr_module_instance = getModule(module_name * MODULE_INSTANCE_NAME)

        if (!isNewModule) return curr_module_static end

        curr_type_name = getAbstractTypeName(javaLib)

        methods = listmethods(lib)
        for method in methods
            method_name = getname(method)

            java_return_type = getname(getreturntype(method))
            java_param_types = getparametertypes(method)

            julia_return_type = getTypeFromJava(java_return_type)

            variables = ""
            julia_param_types = ""
            julia_var_w_types = ["()"]

            if length(java_param_types) != 0
                variables = getVariablesForFunction(java_param_types)
                julia_param_types = getJuliaParamTypesForFunction(java_param_types)
                julia_var_w_types = getJuliaVariablesWithTypes(java_param_types)
            end

            if isStatic(method)
                for var_types in julia_var_w_types
                    if isJavaObject(getreturntype(method)) && occursin("<:Any", var_types)
                        julia_return_type = "T"
                    end
                    
                    method_to_parse = isPrimitive(java_return_type) ? 
                        createStaticPrimitiveFunction(method_name, var_types, lib, julia_return_type, julia_param_types, variables) :
                        createStaticNonPrimitiveFunction(method_name, var_types, java_return_type, curr_type_name, lib, julia_return_type, julia_param_types, variables)
                    Base.eval(curr_module_static, Meta.parse(method_to_parse))
                end
            else
                julia_var_w_types = getJuliaVariablesWithTypes(java_param_types, true)
                for var_types in julia_var_w_types
                    if isJavaObject(getreturntype(method)) && occursin("<:Any", var_types)
                        julia_return_type = "T"
                    end

                    method_to_parse = isPrimitive(java_return_type) ? 
                        createInstancePrimitiveFunction(method_name, var_types, julia_return_type, julia_param_types, variables) :
                        createInstanceNonPrimitiveFunction(method_name, var_types, java_return_type, curr_type_name, julia_return_type, julia_param_types, variables)

                    Base.eval(curr_module_instance, Meta.parse(method_to_parse))
                end
            end
        end

        # Add instance methods to module
        for method in methods
            method_name = getname(method)

            if !isStatic(method)
                Base.eval(curr_module_instance, Meta.parse(createMainInstanceFunction(method_name)))
            end
        end
        
        if (javaLib != "java.lang.Class")
            addConstructors(javaLib, curr_type_name, lib, curr_module_static, curr_module_instance)
            addConstantsAndFields(javaLib, curr_type_name, lib, curr_module_static)
        end

        curr_module_static
    end

    export getInstanceModule, getReturnValue, getTypesConvertion, importJavaLib, JavaValue # FIXME: ON DELIVERY remove JavaValue?
end