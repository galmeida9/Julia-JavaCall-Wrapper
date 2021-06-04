module JavaValueModule
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
    Base.propertynames(obj::JavaValue) = filter(m -> 
            !occursin("#", String(m)) && !occursin("_", String(m)),
        names(getfield(obj, :methods),all=true)
    )

    export JavaValue, _getRef, _getMethods, java_lang_Object
end

module JavaImport

    # IMPORTS #
    using JavaCall, Main.JavaValueModule
    
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
            print(io, nothing)
        else
            print(io, jcall(obj, "toString", JString, ()))
        end
    end

    # Print Boolean correctly in IO
    Base.show(io::IO, obj::jboolean) = print(io, Bool(obj))

    # Override JavaCall error handling to throw julia errors without printing the Java error
    get_error_override = "function JavaCall.geterror(allow=false)
        isexception = JNI.ExceptionCheck()
    
        if isexception == JNI_TRUE
            jthrow = JNI.ExceptionOccurred()
            jthrow==C_NULL && throw(\"Java Exception thrown, but no details could be retrieved from the JVM\")
            JNI.ExceptionClear()
            jclass = JNI.FindClass(\"java/lang/Throwable\")
            jclass==C_NULL && throw(\"Java Exception thrown, but no details could be retrieved from the JVM\")
            jmethodId=JNI.GetMethodID(jclass, \"toString\", \"()Ljava/lang/String;\")
            jmethodId==C_NULL && throw(\"Java Exception thrown, but no details could be retrieved from the JVM\")
            res = JNI.CallObjectMethodA(jthrow, jmethodId, Int[])
            res==C_NULL && throw(\"Java Exception thrown, but no details could be retrieved from the JVM\")
            msg = unsafe_string(JString(res))
            JNI.DeleteLocalRef(jthrow)
            throw(string(\"Error calling Java: \",msg))
        else
            if allow==false
                return #No exception pending, legitimate NULL returned from Java
            else
                throw(\"Null from Java. Not known how\")
            end
        end
    end"
    
    Base.eval(JavaCall, Meta.parse(get_error_override))
    
    # Converts Java types into Julia types
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

    # Converts Julia types into JavaCall types
    function getTypesConvertion(value)
        # Get generic type, without parametric types
        generic_type(::Type{T}) where T = eval(nameof(T))
        type = generic_type(typeof(value))

        types_convertion = Dict(
            Bool        => (x) -> jcall(JavaObject{Symbol("java.lang.Boolean")}, "valueOf", JavaObject{Symbol("java.lang.Boolean")}, (JString,), String(Symbol(x))),
            String      => (x) -> convert(JString, x),
            Char        => (x) -> jcall(JavaObject{Symbol("java.lang.String")}, "valueOf", JavaObject{Symbol("java.lang.String")}, (jchar,), x),
            Int64       => (x) -> convert(JavaObject{Symbol("java.lang.Long")}, x),
            Int32       => (x) -> convert(JavaObject{Symbol("java.lang.Integer")}, x),
            Int16       => (x) -> convert(JavaObject{Symbol("java.lang.Short")}, x),
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

    # Returns value to be used to instantiate a JavaValue (non-primitives)
    function getReturnValue(ref)
        if typeof(ref) == String
            ref = JString(ref)
        end
        ref
    end
    
    # Returns the value mapped to a Vector of JavaValue if it is a vector of JavaObjects, otherwise returns itself
    # This function is only called on primitive functions (which is the case of arrays)
    function mapVectorToJavaValue(value)
        if !(typeof(value) <: Vector{T} where (T <: JavaObject))
            return value
        end

        map(el -> 
            begin
                if !isnull(el)
                    class_name = getname(getclass(el))
                    curr_module = getInstanceModule(class_name)
                    curr_type_name = getAbstractTypeName(class_name)
                    curr_type = Base.eval(Meta.parse(curr_type_name))

                    el_type = JavaObject{Symbol(class_name)}
                    new_el = convert(el_type, el)
                    Main.JavaValue{curr_type}(new_el, curr_module)
                end
            end,
            value)
    end

    # Returns true if the Java type is a primitive type
    function isPrimitive(javaType)
        javaType in ["boolean", "char", "int", "long", "float", "double", "void", "byte", "short"] || occursin("[]", javaType)
    end

    # Returns true if the Java type is an array of objects
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
                                using Main, Main.JavaValueModule, Main.JavaImport, JavaCall
                                end")
                )
            ]
        end
    end

    # Check if a method is static
    function isStatic(meth::JMethod)
        modifiersLib = @jimport java.lang.reflect.Modifier
        modifiers = jcall(meth, "getModifiers", jint, ())
        isMethodStatic = jcall(modifiersLib, "isStatic", jboolean, (jint,), modifiers)
        isMethodStatic != 0
    end

    # Check if it is an interface
    function isInterface(class_name)
        if isPrimitive(class_name)
            return false
        end

        is_interface = jcall(classforname(class_name), "isInterface", jboolean, ())
        is_interface == 1
    end

    # Returns the module with instance methods for a given Java type
    function getInstanceModule(java_return_type)
        module_name = replace(java_return_type, '.' => '_')
        isNewModule, curr_module_instance = getModule(module_name * MODULE_INSTANCE_NAME)

        if (isNewModule)
            importJavaLib(java_return_type)
        end

        curr_module_instance
    end

    # Returns the name of the abstract struct for inheritance purposes
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

    # Returns a string containing the variables to be used in jcall, e.g: "x1, x2, ..."
    function getVariablesForFunction(params)
        join(
            map(type -> "x$(type[1])", enumerate(params) )
            , ", "
        ) * ", "
    end

    # Returns a string containing the types of the parameters to be used in jcall, e.g: "jint, JObject, JString, ..."
    function getJuliaParamTypesForFunction(java_param_types)
        join(map(type -> isJavaObject(type[2]) ? "JObject" : getTypeFromJava(getname(type[2])), enumerate(java_param_types)), ", ") * ","
    end

    # Returns a string containing the arguments and types for the function to be defined, e.g: "(x1::String, x2::T1) where {T1<:Any}"
    function getJuliaVariablesWithTypes(java_param_types, instance = false)
        # function parameters with concrete type
        params = "("
        # where tag types, e.g: where {T<:type}
        where_tag = ""
        # function parameter wrapped in a JavaValue struct
        params_jv = "("
        # where tag for JavaValues
        where_tag_jv = ""

        if instance
            params    = params    * "instance, "
            params_jv = params_jv * "instance, "
        end

        for (index, type) in enumerate(java_param_types)
            if isJavaObject(type)
                params       = params       * "x$(index)::T$(index), "
                where_tag    = where_tag    * "T$(index)<:Any, "

                params_jv    = params_jv    * "x$(index)::JavaValue{T$(index)}, "
                where_tag_jv = where_tag_jv * "T$(index)<:Main.java_lang_Object, "
            elseif isArrayOfJavaObject(type)        
                params_jv    = params_jv    * "x$(index)::Vector{JavaValue{T$(index)}}, "
                where_tag_jv = where_tag_jv * "T$(index)<:Main.java_lang_Object, "

                params       = params       * "x$(index)::Vector{T$index}, "
                where_tag    = where_tag    * "T$(index)<:Any, "
            elseif isInterface(getname(type))
                params       = params       * "x$(index)::JavaValue{T$(index)}, "
                where_tag    = where_tag    * "T$(index)<:Any, "

                params_jv    = params_jv    * "x$(index)::JavaValue{T$(index)}, "
                where_tag_jv = where_tag_jv * "T$(index)<:$(getAbstractTypeName(getname(type))), "
            elseif isStringType(type)
                params       = params       * "x$(index)::String, "

                params_jv    = params_jv    * "x$(index)::JavaValue{T$(index)}, "
                where_tag_jv = where_tag_jv * "T$(index)<:$(getAbstractTypeName(getname(type))), "
            elseif !isPrimitive(getname(type))
                params_jv    = params_jv    * "x$(index)::JavaValue{T$(index)}, "
                where_tag_jv = where_tag_jv * "T$(index)<:$(getAbstractTypeName(getname(type))), "

                params       = params_jv
                where_tag    = where_tag_jv
            else
                params       = params       * "x$(index)::$( getTypeFromJava(getname(type), false) ), "
                params_jv    = params_jv    * "x$(index)::$( getTypeFromJava(getname(type), false) ), "
            end
        end

        params     = params * ")"
        params_jv  = params_jv * ")"
        all_params = []

        if params != "()"
            res_params = where_tag == ""    ? params : "$params where {$where_tag}"
            push!(all_params, res_params)
        end

        if params_jv != "()"
            res_params = where_tag_jv == "" ? params_jv : "$params_jv where {$where_tag_jv}"
            push!(all_params, res_params)
        end

        all_params
    end

    # Returns code to be used in java functions that converts the argumets into the correct types, e.g: int -> java.lang.Integer
    function getAllVariablesConverted(variables)
        curr_variables = split(variables, ", ", keepempty=false)
        res = ""
        for var in curr_variables
            res *= "$var = getTypesConvertion($var)\n"
        end
        res
    end

    # Creates a static function that returns a primitive type
    function createStaticPrimitiveFunction(method_name, julia_var_w_types, lib, julia_return_type, julia_param_types, variables)
        "function $method_name$julia_var_w_types
            $(getAllVariablesConverted(variables))
            value = jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
            mapVectorToJavaValue(value)
        end"
    end

    # Creates a static function that returns a non primitive type
    function createStaticNonPrimitiveFunction(method_name, julia_var_w_types, java_return_type, jv_type_name, lib, julia_return_type, julia_param_types, variables)
        "function $method_name$julia_var_w_types
            $(getAllVariablesConverted(variables))
            curr_module = getInstanceModule(\"$java_return_type\")
            return_value = jcall($lib, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
            return_value = getReturnValue(return_value)
            JavaValue{$jv_type_name}(return_value, curr_module) 
        end"
    end

    # Creates an instance function that returns a primitive type
    function createInstancePrimitiveFunction(method_name, julia_var_w_types, julia_return_type, julia_param_types, variables)
        "function _$method_name$julia_var_w_types
            $(getAllVariablesConverted(variables))         
            value = jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
            mapVectorToJavaValue(value)
        end"
    end

    # Creates an instance function that returns a non primitive type
    function createInstanceNonPrimitiveFunction(method_name, julia_var_w_types, java_return_type, jv_type_name, julia_return_type, julia_param_types, variables)
        "function _$method_name$julia_var_w_types
            $(getAllVariablesConverted(variables))
            curr_module = getInstanceModule(\"$java_return_type\")
            return_value = jcall(instance, \"$method_name\", $julia_return_type, ($julia_param_types), $variables)
            return_value = getReturnValue(return_value)
            JavaValue{$jv_type_name}(return_value, curr_module)
        end"
    end

    # Main function for instance methods that enables overloading of methods
    function createMainInstanceFunction(method_name)
        "function $method_name(instance)
            function (args...)
                _$method_name(instance, args...)
            end
        end"
    end

    # Adds Class's constants and fields to the static module to be returned to the user
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
                field_to_parse =
                "$field_name = 
                (function() 
                    return_value = (function()
                                        cls = classforname(\"$javaLib\")
                                        jcall(cls, \"getField\", JField, (JString, ), \"$field_name\")($lib)
                                    end)()
                    return_value = getReturnValue(return_value)
                    JavaValue{$jv_type_name}(
                        return_value,
                        getInstanceModule(\"$java_field_type\")
                    )
                end)()"
                Base.eval(curr_module_static, Meta.parse(field_to_parse))
            end
        end
    end

    # Adds Class's constructors to the static module to be returned to the user
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
            for var_types in julia_variables_with_types
                method_to_parse = "function new$var_types
                                        $(getAllVariablesConverted(variables))
                                        return_value = ($lib)(($julia_param_types), $variables)
                                        return_value = getReturnValue(return_value)
                                        JavaValue{$jv_type_name}(return_value, $curr_module_instance)
                                    end"
                Base.eval(curr_module_static, Meta.parse(method_to_parse))
            end
        end
    end

    """
    ```
    importJavaLib(javaLib)
    ```
    Imports a Java library
    ### Args
    * javaLib: The Java library

    ### Returns
    Module containing the static methods and contructors with the new method
    """
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

    export getInstanceModule, getReturnValue, mapVectorToJavaValue, getTypesConvertion, importJavaLib, JavaValue # FIXME: ON DELIVERY remove JavaValue?
end