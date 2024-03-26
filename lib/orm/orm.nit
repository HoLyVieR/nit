module orm is
	new_annotation field
	new_annotation table
	new_annotation named
	new_annotation translated_by
end

class OrmFieldInfo
    var field_name : String
    var field_value: nullable Object
    var field_type: String
    var translator : nullable String

    fun get_field_name: String
    do
        return self.field_name
    end

    fun get_field_value: nullable Object
    do
        return self.field_value
    end

    fun get_field_type: Object
    do
        return self.field_type
    end

    fun get_translator: nullable String
    do
        return self.translator
    end
end

abstract class ConcretizableQuery
    super Array[HashMap[String, Object]]

    private var is_concretized = false

    fun concretize is abstract

    fun ensure_concretization do
        if not is_concretized then
            self.concretize
            self.is_concretized = true
        end
    end

    redef fun iterator do
        self.ensure_concretization
        return super
    end

    redef fun [](index) do
        self.ensure_concretization
        return super(index)
    end
end

class SelectQuery
    super ConcretizableQuery

    fun from_object(object_name : String): SelectQuery do
        return self
    end

    fun where(condition: String, mapped: Array[Object]) : SelectQuery do
        return self
    end

    redef fun concretize do
        var map = new HashMap[String, Object]
        map["id"] = 123
        self.add(map)
    end
end

fun select: SelectQuery do
    return new SelectQuery
end

abstract class OrmTranslator[T]
    fun from_db(o : nullable Object) : T is abstract
    fun to_db(o : T) : nullable Object is abstract
end
