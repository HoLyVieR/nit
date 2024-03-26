module orm is
	new_annotation field
	new_annotation table
	new_annotation named
	new_annotation translated_by
end

import sqlite3

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

class OrmMapper
    fun create_and_map(class_type: String, raw_data: HashMap[String, nullable Object]): Object do
        var inst = self.create_class(class_type).as(OrmTable)
        inst.orm_write_fields(raw_data)
        return inst
    end

    # Method is constructed during the compilation phase
    fun create_class(class_type: String): Object do
        print("Type missing : " + class_type)
        abort
    end

    fun get_db_name_of_class(class_type: String): String do
        return class_type
    end

    fun get_db_fields_of_class(class_type: String): Array[String] do
        var inst = create_class(class_type)
        var fields = inst.as(OrmTable).orm_read_fields
        var result = new Array[String]

        for field in fields do
            result.add field.get_field_name
        end

        return result
    end
end

abstract class ConcretizableQuery[T]
    super Collection[T]

    private var is_concretized = false
    private var concretized_value : Array[T] = new Array[T]

    fun concretize : Array[T] is abstract

    fun ensure_concretization do
        if not is_concretized then
            self.concretized_value = self.concretize
            self.is_concretized = true
        end
    end

    redef fun iterator do
        self.ensure_concretization
        return self.concretized_value.iterator
    end
end

class SelectQuery
    super ConcretizableQuery[Object]

    var connection : Sqlite3DB

    var from_type: String = ""
    var where_condition : String = "1 = 1"
    var where_typed_value : Array[Object] = new Array[Object]

    fun from(object_name : String): SelectQuery do
        self.from_type = object_name
        return self
    end

    fun where(condition: String, mapped: Array[Object]) : SelectQuery do
        if self.where_condition != "" then
            self.where_condition += " and "
        end

        self.where_condition += condition
        self.where_typed_value += mapped
        return self
    end

    fun replace_token(query: String, values : Array[Object]): String do
        var min_position = 0

        for entry in values do
            var position = query.index_of_from('?', min_position)
            var text_substitute = ""

            if entry isa Numeric then
                text_substitute = entry.to_s
            else if entry isa String then
                text_substitute = entry.to_sql_string
            else if entry isa Bool then
                if entry then
                    text_substitute = "TRUE"
                else
                    text_substitute = "FALSE"
                end
            else
                assert false
            end

            query = query.substring(0, position) + text_substitute + query.substring_from(position + 1)
            min_position = position + text_substitute.length
        end

        return query
    end

    redef fun concretize do
        var mapper = new OrmMapper
        var mapped_fields = mapper.get_db_fields_of_class(self.from_type)

        var query = ""
        query += mapped_fields.join(", ") + " "
        query += "FROM " + mapper.get_db_name_of_class(self.from_type) + " "
        query += "WHERE " + self.replace_token(self.where_condition, self.where_typed_value)

        var statement = self.connection.select(query)
        assert statement != null

        var result = new Array[Object]
        for row in statement do
            var entry = new HashMap[String, nullable Object]
            for i in [0..mapped_fields.length[ do
                entry[mapped_fields[i]] = row[i].value
            end
            result.add(mapper.create_and_map(self.from_type, entry))
        end
        
        return result
    end
end

class OrmOperation
    var connection : Sqlite3DB

    fun select: SelectQuery do
        return new SelectQuery(connection)
    end
end

fun with_db(path: String): OrmOperation
do
    var connection = new Sqlite3DB.open(path)
    return new OrmOperation(connection)
end

abstract class OrmTable
    fun orm_write_fields(data : HashMap[String, nullable Object]) is abstract
    fun orm_read_fields: Array[OrmFieldInfo] is abstract
end

abstract class OrmTranslator[T]
    fun from_db(o : nullable Object) : T is abstract
    fun to_db(o : T) : nullable Object is abstract
end
