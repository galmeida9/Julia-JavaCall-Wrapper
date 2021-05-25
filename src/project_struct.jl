module project_struct
    using JavaCall
    struct JavaValue
        ref::JavaObject
        methods::Module
    end
    export JavaValue
end