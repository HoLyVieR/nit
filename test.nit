module test

import orm

class DecoratedIntTranslator
    super OrmTranslator[Int]

    redef fun from_db(o) do
        assert o isa String
        o = o.substring(2, o.length - 4)
        return o.to_n.as(Int)
    end

    redef fun to_db(o) do
        return "--" + o.to_s + "--"
    end
end

class MyTestClass
    table

    var field1 : Int = 0 is field, named "id"
    var field2 : Int = 0 is field, translated_by "DecoratedIntTranslator"
end


var result = select.from_object("MyTestClass").where("id = ?", [123])

for value in result
do
    print("Value : " + value["id"].to_s)
end

var inst: MyTestClass = new MyTestClass

# Test d'écriture de contenu dans un objet
var data = new HashMap[String, Object]
data["id"] = 123
data["field2"] = "--345--"
inst.orm_write_fields(data)

# Test de lecture de contenu d'un objet
for field in inst.orm_read_fields
do
    print("Field : {field.get_field_name} = {field.get_field_value.to_s} ({field.get_field_type})")
end
