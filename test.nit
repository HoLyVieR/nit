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

var query = with_db("test.sqlite3").
    select.
    from("MyTestClass").
    where("id = ?", [555])

for value in query
do
    value = value.as(MyTestClass)
    print("Value Field 1 : " + value.field1.to_s)
    print("Value Field 2 : " + value.field2.to_s)
end
