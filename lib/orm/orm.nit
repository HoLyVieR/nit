module orm is
	new_annotation field
	new_annotation table
	new_annotation named
	new_annotation translated_by
    new_annotation primary
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
    fun create_and_map(class_type: String, raw_data: HashMap[String, nullable Object]): OrmTable do
        var inst = self.create_class(class_type).as(OrmTable)
        inst.orm_write_fields(raw_data)
        inst._orm_is_new = false
        return inst
    end

    # Method is constructed during the compilation phase
    fun create_class(class_type: String): Object do
        print("Type missing : " + class_type)
        abort
    end

    fun get_db_name_of_class(class_type: String): String do
        var inst = self.create_class(class_type).as(OrmTable)
        return inst.orm_get_table
    end

    fun get_db_fields_of_class(class_type: String): Array[String] do
        var inst = create_class(class_type).as(OrmTable)
        return self.get_db_fields_of_type(inst)
    end

    fun get_db_fields_of_type(obj: OrmTable): Array[String] do
        var fields = obj.orm_read_fields
        var result = new Array[String]

        for field in fields do
            result.add field.get_field_name
        end

        return result
    end

    fun object_to_sql_string(o : nullable Object): String do
        if o == null then
            return "null"
        else if o isa Numeric or o isa Bool then
            return o.to_s
        else if o isa String then
            return o.to_sql_string
        end

        assert false
        return ""
    end
end

abstract class ConcretizableQuery[T]
    var is_concretized = false
    var concretized_value : Array[T] = new Array[T]

    fun concretize : Array[T] is abstract

    fun execute do
        self.ensure_concretization
    end

    fun ensure_concretization do
        if not is_concretized then
            self.concretized_value = self.concretize
            self.is_concretized = true
        end
    end
end

abstract class IterableQuery[T]
    super Collection[T]
    super ConcretizableQuery[T]

    redef fun first do
        self.ensure_concretization
        return self.concretized_value.first
    end

    redef fun iterator do
        self.ensure_concretization
        return self.concretized_value.iterator
    end
end

class SelectQuery
    super IterableQuery[OrmTable]

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

        var result = new Array[OrmTable]
        for row in statement do
            var entry = new HashMap[String, nullable Object]
            for i in [0..mapped_fields.length[ do
                entry[mapped_fields[i]] = row[i].value
            end

            var obj_entry = mapper.create_and_map(self.from_type, entry)
            obj_entry.orm_saved_db = new OrmOperation(connection)
            result.add(obj_entry)
        end

        return result
    end
end

class InsertQuery
    super ConcretizableQuery[OrmTable]

    var connection : Sqlite3DB

    var from_type: String = ""
    var values = new Array[OrmTable]

    fun into(object_name : String): InsertQuery do
        self.from_type = object_name
        return self
    end

    fun value(data : OrmTable): InsertQuery do
        assert data.orm_get_table == self.from_type
        self.values.add data
        return self
    end

    redef fun concretize do
        var mapper = new OrmMapper
        var mapped_fields = mapper.get_db_fields_of_class(self.from_type)

        assert self.values.length > 0

        var query = ""
        query += "INTO " + mapper.get_db_name_of_class(self.from_type) + ""
        query += "(" + mapped_fields.join(", ") + ") "
        query += "VALUES "
        var is_first = true

        for data in self.values do
            query += "("
            for field in data.orm_read_fields do
                query += mapper.object_to_sql_string(field.get_field_value)
                query += ","
            end

            query = query.substring(0, query.length - 1)
            query += "),"
        end

        query = query.substring(0, query.length - 1)

        var statement = self.connection.insert(query)
        assert statement

        return new Array[OrmTable]
    end
end

class UpdateQuery
    var connection : Sqlite3DB

    fun value(data : OrmTable) do
        var mapper = new OrmMapper
        var mapped_fields = mapper.get_db_fields_of_type(data)

        var primary_field = data.orm_get_primary_key
        var primary_condition = ""
        var query = "UPDATE "
        query += data.orm_get_table + " "
        query += "SET "

        for field in data.orm_read_fields do
            var condition = ""
            condition += field.get_field_name + " = "
            condition += mapper.object_to_sql_string(field.get_field_value)

            if field.get_field_name == primary_field then
                primary_condition = condition
            else
                query += condition
                query += ","
            end
        end

        query = query.substring(0, query.length - 1)
        query += " WHERE "
        query += primary_condition

        var statement = self.connection.execute(query)
        assert statement
    end
end

class OrmOperation
    var connection : Sqlite3DB

    fun select: SelectQuery do
        return new SelectQuery(connection)
    end

    fun insert: InsertQuery do
        return new InsertQuery(connection)
    end

    fun update: UpdateQuery do
        return new UpdateQuery(connection)
    end
end

fun with_db(path: String): OrmOperation
do
    var connection = new Sqlite3DB.open(path)
    return new OrmOperation(connection)
end

abstract class OrmTable
    var orm_is_new : Bool = true
    var orm_saved_db : nullable OrmOperation = null

    fun save do
        assert not self.orm_is_new
        assert self.orm_saved_db != null
        self.orm_saved_db.update.value(self)
    end

    fun orm_write_fields(data : HashMap[String, nullable Object]) is abstract
    fun orm_read_fields: Array[OrmFieldInfo] is abstract
    fun orm_get_table: String is abstract
    fun orm_get_primary_key: String is abstract
end

abstract class OrmTranslator[T]
    fun from_db(o : nullable Object) : T is abstract
    fun to_db(o : T) : nullable Object is abstract
end
